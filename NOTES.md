# NOTES

Design notes and written answers for each task. File references are relative to
the repo root.

---

## Task 1: Multi-instance EC2 provisioning

**Where:** [`modules/ec2-fleet`](modules/ec2-fleet) (module) and [`envs/dev`](envs/dev) (root that calls it; the 5 instances are in `terraform.tfvars`).

| Name         | Instance type | Root volume | Size (GiB) | IOPS | Key pair         | Protected |
|--------------|---------------|-------------|-----------:|-----:|------------------|:---------:|
| `web-01`     | t3.micro      | gp3         | 20         | 3000 | `web-01-key`     |           |
| `app-01`     | t3.small      | gp2         | 30         | n/a  | `app-01-key`     |           |
| `db-primary` | m5.large      | **io2**     | 100        | 5000 | `db-primary-key` | **yes**   |
| `cache-01`   | r5.large      | **io1**     | 50         | 2500 | `cache-01-key`   |           |
| `batch-01`   | c5.large      | standard    | 40         | n/a  | `batch-01-key`   |           |

How each requirement is met:

- **One input variable drives all 5.** `var.instances` is a `map(object)` keyed by instance name, and the module iterates over it with `for_each`. There are no per-instance resource blocks. Map keys, not list indexes, are the resource addresses, so removing one entry never shifts or recreates the others.
- **Different instance type, volume type, volume size and key pair.** These values are set in the tfvars. The module enforces unique `key_name`s through variable validation, and `envs/dev/tests` checks that the other three attributes are all different.
- **io1/io2.** `db-primary` uses io2 and `cache-01` uses io1. The module validates the IOPS rules: IOPS are required for io1/io2, io1 allows up to 50 IOPS/GiB, and io2 up to 1000 IOPS/GiB. It also rejects `st1`/`sc1`, because EC2 cannot boot from them. (I didn't spend a slot on st1 because it isn't a valid root volume type. `standard` is the fifth bootable type.)
- **Tags.** `Name`, `Environment` and `Owner` go on every instance and its root volume. They are merged in *last*, so a caller's `tags` map can't override them (there's a test for this).
- **Outputs.** `instance_ids` (name → ID) and `private_ips` (name → private IP).
- **Additional hardening:** IMDSv2 is required, root volumes are encrypted, and `ignore_changes = [ami]` stops a newly published AMI from replacing running hosts.

### Which instance has `prevent_destroy`, and why

**`db-primary`.** It is the only stateful, hard-to-recreate node in the set. It is the primary database on an io2 volume. Losing it means data loss plus a restore from backup, and that costs far more than rebuilding a stateless web, app, batch or cache node, which config management or an ASG can replace in minutes. It is also the node most likely to be caught by an accidental forced replacement, for example if someone changes `instance_type` or `subnet_id`, or runs `terraform destroy` against the wrong workspace.

### The Terraform constraint, and how I worked around it

`lifecycle` meta-arguments must be literal values. `prevent_destroy = each.value.x` is a parse error. So one `for_each` block cannot protect "just one" of its instances. The module therefore splits the single `var.instances` map into two `for_each` sets:

- `aws_instance.standard` covers everything with `prevent_destroy = false`.
- `aws_instance.protected` is the same config plus `lifecycle { prevent_destroy = true }`.

Both are still driven by the one variable, and callers choose protection per instance with a flag. The protected instance also has `disable_api_termination = true`. `prevent_destroy` only stops *Terraform*; termination protection also blocks the console, the CLI and other tools.

**Trade-off:** flipping `prevent_destroy` on an existing instance changes its address (`standard["x"]` ↔ `protected["x"]`). You must pair that change with a `moved {}` block or `terraform state mv`, or Terraform will plan a replacement.

### Key pairs

By default each `key_name` must already exist, because I don't want Terraform generating private keys that end up in state. If an entry sets `public_key`, the module creates that `aws_key_pair` itself.

---

## Task 2: Remote state and locking

**Where:** [`envs/dev/backend.tf`](envs/dev/backend.tf) (the backend) and [`bootstrap/state-backend`](bootstrap/state-backend) (creates the bucket and table).

- **S3 bucket:** versioned (so you can roll back a corrupted state), SSE-KMS with a rotating CMK, all public access blocked, `BucketOwnerEnforced`, a TLS-only bucket policy, old versions expire after 90 days, and `prevent_destroy`.
- **DynamoDB table** `terraform-state-locks`: hash key `LockID` (string), on-demand billing, PITR, deletion protection and `prevent_destroy`.
- The bootstrap stack uses **local state on purpose**. It can't keep its state in a bucket it hasn't created yet. Once it has been applied, it can be migrated into the bucket.

Order of operations: `bootstrap/state-backend` → `terraform apply`, then `envs/dev` → `terraform init` (use `-migrate-state` if a local state already exists) → `plan`/`apply`.

### What happens today, with local state, if two people apply at the same time

With local state, each engineer has their **own `terraform.tfstate` on their own laptop**. Nothing is shared and nothing is locked. (Terraform's local lock file only protects against two processes on the same machine.)

1. Alice and Bob both run `apply`. Each plan is computed from that person's *own* state file, so neither sees what the other is about to do.
2. Both call the AWS APIs at once. You get **duplicate resources** (both create "web-01", so there are two instances), or errors from name collisions (key pairs, IAM names), or one person's change silently reverts the other's.
3. Each person writes a state file that records only *their* view. The states have now **diverged from reality and from each other**. The next plan from either laptop tries to "fix" things the other person created: it recreates them, deletes them, or leaves orphaned resources that nobody's state tracks and that keep costing money.
4. Even if one person ran the command alone, the state (which can include secrets) lives on a single laptop, with no backup, no history and no audit trail.

### How the backend change prevents it

- **A single source of truth.** Everyone reads and writes the same object, `s3://…/ec2-fleet/dev/terraform.tfstate`, so plans are always computed against the latest state.
- **Mutual exclusion.** Before any state-changing operation (`plan` with refresh, `apply`, `destroy`, `import` …), Terraform writes a lock item to DynamoDB, keyed by `LockID` = `<bucket>/<key>`, using a **conditional put** that only succeeds if no lock item exists. DynamoDB guarantees that conditional write is atomic, so only one run can win. Bob's run fails straight away with `Error acquiring the state lock`, showing who holds the lock and since when. It can wait with `-lock-timeout=5m`. Once Alice finishes and the lock is released, Bob's next plan sees her changes.
- **Integrity and recovery.** Terraform also stores the state's MD5 digest in the table, so it can detect a stale or partially written read. S3 versioning lets you roll back a bad write. If a crashed run leaves a stale lock, `terraform force-unlock <id>` clears it, and only after confirming that the run is really dead.

> **Note (modern alternative):** Terraform ≥ 1.10 supports S3-native locking (`use_lockfile = true`, based on S3 conditional writes), and HashiCorp has since **deprecated** `dynamodb_table`. Recent Terraform versions print a deprecation warning at `init`. The brief explicitly asks for DynamoDB, so that's what is configured. For a new setup today I'd use `use_lockfile = true` and drop the table. During a migration both can be enabled at the same time.

---

## Task 3: Multi-account IAM and cross-account access

**Where:** [`iam/`](iam). It is one configuration with two aliased providers (`aws.account_a`, `aws.account_b`). Each alias is pinned with `allowed_account_ids`, so a mis-set profile fails instead of writing IAM into the wrong account.

### Account A (000000000000)

| Item | Implementation |
|------|----------------|
| `group1`, programmatic only: `engine`, `ci` | Users under path `/programmatic/`, with **no login profile**. A group guardrail denies `iam:Create/Update/DeleteLoginProfile`, so a console password can never be added later. Access keys are only created when a `pgp_key` is supplied, so state only ever holds ciphertext. |
| `group2`, console + CLI: `alice`, `bob` | Users under `/humans/`, with a login profile (PGP-encrypted, reset on first sign-in) and self-service access keys. The group policy lets them manage their own password, MFA device and keys, and **denies everything else until they sign in with MFA**. It also lets them assume roleA and roleB with MFA. |
| `roleA`, admin except IAM | `Allow NotAction: iam:*` on `*`, plus one exception, `iam:CreateServiceLinkedRole`. Many services (ECS, ELB, RDS, …) have to create their service-linked role on first use. Service-linked role permissions are defined by AWS, so this can't escalate privileges. Trust: only the group2 users, **with MFA**. |
| `roleB`, may only assume a role in Account B | A single statement: `sts:AssumeRole` on `arn:aws:iam::111111111111:role/roleC`, and nothing else. Trust: the `engine` user, and the group2 humans with MFA. |

### Account B (111111111111)

| Item | Implementation |
|------|----------------|
| `roleC` | Trust policy principal = **`arn:aws:iam::000000000000:role/roleB`** (exact ARN). Permissions: `s3:*` on `arn:aws:s3:::acme-account-b-shared-data` and `…/*` only. The bucket is created in Account B with public access blocked and default encryption. |

Cross-account access needs **both sides** to allow it. roleB's identity policy allows `sts:AssumeRole` on roleC, and roleC's trust policy allows roleB. If either side is missing, the call gets `AccessDenied`. In Terraform, roleC's trust policy references `aws_iam_role.roleB.arn`, which also makes Terraform create roleB first. IAM rejects a trust policy whose principal doesn't exist yet.

**Interpretation / assumptions (flagged explicitly):**
- The brief doesn't say who may assume roleA/roleB. I chose group2 humans (with MFA) for both, and `engine` for roleB. `ci` is deliberately left out, because Task 4 defines its complete permission set.
- I read "full console + CLI access" for group2 as the *access channels* (a password plus access keys), not as `AdministratorAccess` on the users. Their admin power comes from assuming roleA with MFA. That is the standard pattern: no standing admin on IAM users. If the grader meant "attach AdministratorAccess to group2", that's a one-line `aws_iam_group_policy_attachment`, and I deliberately didn't add it.
- `roleA`'s `NotAction iam:*` also excludes `iam:PassRole`. As a result roleA **can't launch EC2 instances with an instance profile or create Lambda/ECS resources that take a role**, which is the price of "except IAM". In a real org I'd allow `iam:PassRole` only on roles under a controlled path (for example `/workload/*`) and pair roleA with an SCP. Without that, an admin-minus-IAM role can still reach IAM through other doors (assuming a more privileged role that trusts the account root, or using `organizations:*` in a management account).

### Q: Would you really give `engine` and `ci` IAM users with access keys in production?

**No.** Long-lived access keys are the most common root cause of AWS credential leaks. They sit in CI variables, laptops, logs and container images. They don't expire, and teams rarely rotate them. For machine identities in production I would do this instead:

- **CI (`ci`)**: use **OIDC federation**. GitHub Actions, GitLab and Bitbucket all issue a signed OIDC token per job. Create an IAM OIDC identity provider and a `ci-deploy` **role** whose trust policy pins `aud = sts.amazonaws.com` and `sub = repo:<org>/<repo>:ref:refs/heads/main` (or a specific `environment:`). The job calls `AssumeRoleWithWebIdentity` and gets credentials that last about an hour. There are no secrets to store or rotate, and the trust can't be reused from a fork or a different branch. The Task 4 policy would be attached to that role rather than to a user.
- **`engine` (a service running on AWS)**: use an **IAM role for the compute it runs on**: an EC2 instance profile, an ECS task role, EKS IRSA or Pod Identity, or a Lambda execution role. The SDK picks up short-lived, automatically rotated credentials from the metadata endpoint.
- **Workloads outside AWS** (on-prem, another cloud): use **IAM Roles Anywhere** with X.509 certificates from your PKI, which again gives short-lived credentials.
- **Humans**: use **IAM Identity Center (SSO)** backed by the corporate IdP, with permission sets and short-lived sessions, rather than IAM users with passwords at all.

If IAM users with keys are truly unavoidable (for example, a third-party SaaS that only accepts keys), the minimum is: one purpose per user, a policy scoped to exactly that purpose, a `aws:SourceIp` or `aws:SourceVpce` condition, keys stored in a secrets manager, rotation every 90 days or less, alarms on unused keys (IAM credential report, Access Analyzer unused access) and on CloudTrail anomalies, and never `CreateAccessKey` on themselves.

### Q: In roleC's trust policy, why does it matter whether you trust Account A's root or roleB's specific ARN?

- **`"AWS": "arn:aws:iam::000000000000:root"`** does *not* mean "only the root user". It means **"I delegate the decision to Account A"**. *Any* principal in Account A whose identity policy allows `sts:AssumeRole` on roleC can then assume it: roleA (its `NotAction iam:*` includes `sts:*`), any admin user, any role with `sts:AssumeRole` on `*`, or a newly created role next year. Account B's data access is then only as tight as Account A's IAM hygiene. It also becomes the **confused-deputy / lateral-movement path**: compromise any over-privileged principal in A, and you reach B's bucket. This directly breaks the requirement that roleC be assumable *only* by roleB.
- **`"AWS": "arn:aws:iam::000000000000:role/roleB"`** means Account B decides **who** may cross, and only roleB gets through, *no matter* what policies anyone in A holds. Both sides still have to agree, but B's side is now the restrictive one. The blast radius stays at "whoever can assume roleB", which Account A controls separately with its own trust policy.
- **Operational nuance:** IAM stores a specific role ARN in a trust policy as the role's **unique ID** (`AROA…`). If roleB is deleted and recreated with the same name, the trust silently breaks (the policy shows the old `AROA…` ID) until roleC's trust policy is saved again. That's usually desirable: a recreated role is a *different* principal. If you want to trust the account but still pin one role *by name*, the pattern is `Principal: {AWS: <account root>}` plus `Condition: ArnEquals aws:PrincipalArn <roleB ARN>`. I use that pattern for roleA/roleB trusting humans in Account A.

---

## Task 4: Least-privilege policy for `ci`

**Where:** template [`iam/policies/ci-least-privilege.json.tftpl`](iam/policies/ci-least-privilege.json.tftpl), rendered example [`iam/policies/ci-least-privilege.rendered.json`](iam/policies/ci-least-privilege.rendered.json), attached to `ci` in [`iam/ci-policy.tf`](iam/ci-policy.tf). It's a customer-managed policy, not an AWS-managed one.

| Sid | Actions | Resource | Why |
|-----|---------|----------|-----|
| `ECRAuthToken` | `ecr:GetAuthorizationToken` | `*` | Needed for `docker login`. The API is registry-wide and **doesn't support resource-level permissions**, so `*` is the only valid value. On its own it grants no repository access. |
| `ECRPushToOneRepository` | `BatchCheckLayerAvailability`, `InitiateLayerUpload`, `UploadLayerPart`, `CompleteLayerUpload`, `PutImage` | `repository/app` | The exact set of calls `docker push` makes. |
| `ECSTaskDefinitions` | `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition` | `*` | Registers the new revision and reads the current one to use as a template. Neither action supports resource-level permissions. |
| `ECSDeployOneService` | `ecs:UpdateService`, `ecs:DescribeServices` | `service/app-cluster/app-service` | Points the service at the new revision and polls until it is stable (`aws ecs wait services-stable`). |
| `PassTaskRolesToECSOnly` | `iam:PassRole` | the task execution role and task role ARNs, **condition** `iam:PassedToService = ecs-tasks.amazonaws.com` | Registering a task definition that references roles *requires* PassRole. This is the permission most often over-granted. Unscoped PassRole lets CI attach *any* role, including an admin role, to a container it controls, which is a textbook privilege escalation. |
| `ListArtifactsBucket` | `s3:ListBucket` | `arn:aws:s3:::acme-build-artifacts` | Lets `aws s3 cp/sync` enumerate keys. Without it, a missing object returns 403 instead of 404. |
| `ReadArtifacts` | `s3:GetObject` | `arn:aws:s3:::acme-build-artifacts/*` | Reads build artifacts. |

### What I deliberately left out, and why

- **No wildcard actions** (`ecr:*`, `ecs:*`, `s3:*`), and no managed policies such as `AmazonEC2ContainerRegistryPowerUser` or `AmazonECS_FullAccess`. They include create/delete/policy-editing actions a pipeline never needs.
- **ECR pull and management**: `BatchGetImage`, `GetDownloadUrlForLayer`, `DescribeImages`, `ListImages`, `BatchDeleteImage`, `CreateRepository`, `DeleteRepository`, `SetRepositoryPolicy`, `PutLifecyclePolicy`, `PutImageTagMutability`. The brief says *push*. Pulls happen through the ECS task execution role, not CI. Delete and policy actions could wipe images or open the repo to other accounts. *(If the build uses the registry as a layer cache, `--cache-from`, add `BatchGetImage` and `GetDownloadUrlForLayer` on the same repo.)*
- **ECS lifecycle**: `CreateService`, `DeleteService`, `DeregisterTaskDefinition`, `RunTask`, `StartTask`, `StopTask`, `ExecuteCommand`, `CreateCluster`, `DeleteCluster`, `UpdateCluster`. CI *deploys a new revision to an existing service*. It doesn't create or delete services, run ad-hoc tasks, or shell into containers (`ExecuteCommand` would give interactive access to production).
- **`ecs:TagResource`**: needed only if the pipeline passes `--tags` to `RegisterTaskDefinition`. Left out until it's actually needed.
- **`ecs:ListTasks`, `DescribeTasks`, `logs:*`**: helpful for debugging a failed rollout, but not required to deploy. They're easy to add read-only if the team wants the pipeline to print failure reasons.
- **Unscoped `iam:PassRole`**: see above. It is scoped to two role ARNs *and* to the ECS tasks service.
- **Any S3 write or delete**: `PutObject`, `DeleteObject`, `PutBucketPolicy`, `PutObjectAcl`. The brief says read-only. Write access would let a compromised pipeline tamper with the artifacts later builds consume, which is a supply-chain risk.
- **`s3:GetObjectVersion`, `ListAllMyBuckets`, `GetBucketLocation`**: not needed to read the current objects in a known bucket.
- **`kms:Decrypt`**: needed *only* if the artifacts bucket uses SSE-KMS with a customer-managed key. In that case add `kms:Decrypt` on that key ARN with `kms:ViaService = s3.<region>.amazonaws.com`. It's left out because the example bucket uses SSE-S3.
- **CodeDeploy, CloudFormation, ELB** permissions: only needed for blue/green or CFN-managed deploys, which the brief doesn't mention.
- **`iam:*`, `sts:AssumeRole`**: CI can't escalate privileges or hop into roleB or roleC.

Further hardening, outside can be added: add an `aws:SourceIp` or `aws:SourceVpce` condition to pin CI to its runners' egress IPs, and preferably move this policy onto an OIDC-assumed role (reference provided in Task 3).

---

## Task 5: Find and fix the bug

**Where:** the original is in [`task5-bugfix/original-broken.tf.txt`](task5-bugfix/original-broken.tf.txt) and the fix in [`task5-bugfix/main.tf`](task5-bugfix/main.tf). The same corrected pattern is used in the real stack at [`iam/account-b.tf`](iam/account-b.tf).

### Bug 1: trust policy, wrong principal type (`user/roleB` → `role/roleB`)

```diff
- identifiers = ["arn:aws:iam::000000000000:user/roleB"]
+ identifiers = ["arn:aws:iam::000000000000:role/roleB"]
```

An IAM ARN encodes the **principal type** as well as the name. `…:user/roleB` refers to an IAM *user* called "roleB", which is a different identity from the *role* roleB. When a role is written into a trust policy, IAM resolves the principal ARN to that entity's unique ID. Since no user called `roleB` exists, `CreateRole` / `UpdateAssumeRolePolicy` fails with `MalformedPolicyDocument: Invalid principal in policy`, and `terraform apply` errors out. Even if someone *had* created a user called roleB, the trust would point at that user, and sessions from the actual roleB (`arn:aws:sts::000000000000:assumed-role/roleB/<session>`) would never match. The result is `AccessDenied` on `sts:AssumeRole`.

### Bug 2: permissions policy, `Resource = "*"`

```diff
- Resource = "*"
+ Resource = [
+   "arn:aws:s3:::<bucket>",
+   "arn:aws:s3:::<bucket>/*",
+ ]
```

`s3:*` on `*` gives roleC full control of **every bucket in Account B**. It can read, overwrite and delete any object, change bucket policies to make data public, and delete buckets. The requirement is full access to a *single named bucket*. This bug doesn't make anything fail. It is a security bug, and a worse one than Bug 1, because it "works". Two ARNs are needed because S3 has two resource types: bucket-level actions (`ListBucket`, `GetBucketPolicy`, `PutBucketVersioning` …) are evaluated against `arn:aws:s3:::bucket`, and object-level actions (`GetObject`, `PutObject`, `DeleteObject` …) against `arn:aws:s3:::bucket/*`. With only one of the two, half of "full access" silently fails with 403.

### Other points about the snippet (not the two graded bugs)

- The snippet has no `provider` for Account B. roleC must be created **in Account B**, so the fixed version pins the provider with `allowed_account_ids = [account_b_id]`.
- The fix on B's side isn't enough by itself. **roleB's own permissions policy in Account A must also allow `sts:AssumeRole` on roleC's ARN.** Cross-account access needs both sides. That is done in `iam/account-a.tf` (`roleB_assume_roleC`).
- roleB must exist before roleC's trust policy is created. In the combined stack, referencing `aws_iam_role.roleB.arn` guarantees that ordering.
