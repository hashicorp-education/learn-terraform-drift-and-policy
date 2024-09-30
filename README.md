---
id: 5d40552a-e0eb-4525-932f-fbb79a48e9f5
name: Detect infrastructure drift and enforce policies
short_name: Drift and policies
products_used:
  - terraform
description: >-
  Use HCP Terraform to enforce policies and detect infrastructure
  configuration drift.
default_collection_context: terraform/cloud
edition: 'tfc:plus'
---

As your organization grows and your infrastructure provisioning workflows
mature, it gets harder to enforce consistency and best practices with training
and hand-built tooling alone. Terraform can automatically check that your
infrastructure satisfies industry best practices and organization-specific
standards, with resource and module-specific conditions, workspace-specific run
tasks, and workspace or organization-wide policies, enforced by HashiCorp
Sentinel or Open Policy Agent (OPA).

<Note>

HCP Terraform **Free** Edition includes one policy set of up to five policies.
In HCP Terraform **Plus** Edition, you can connect a policy set to a version
control repository or create policy set versions via the API. Refer to [HCP
Terraform pricing](https://www.hashicorp.com/products/terraform/pricing) for
details.

</Note>

In this tutorial, you will use both Terraform preconditions and policies to
validate configuration and enforce compliance with organizational practices.
First, you will use Terraform preconditions to enforce network security
conventions. Then, you will learn how to configure and enforce policies in HCP
Terraform, preventing infrastructure deployments on certain days of the week.
Finally, you will use HCP Terraform's drift detection to detect when
infrastructure settings have diverged from your written Terraform configuration.

Pre- and post-conditions help you define resource requirements in Terraform
configurations. By including custom conditions in module definitions, you can
ensure that downstream consumers comply with configuration standards, and use
modules properly.

## Prerequisites 

This tutorial assumes that you are familiar with the Terraform and HCP Terraform
workflows. If you are new to Terraform, complete the [Get Started
tutorials](/terraform/tutorials/aws-get-started) first. If you are new to HCP
Terraform, complete the [HCP Terraform Get Started
tutorials](/terraform/tutorials/cloud-get-started) first. 

In order to complete this tutorial, you will need the following:

- Terraform v1.4+ [installed locally](/terraform/tutorials/aws-get-started/install-cli).
- An [AWS account](https://portal.aws.amazon.com/billing/signup?nc2=h_ct&src=default&redirect_url=https%3A%2F%2Faws.amazon.com%2Fregistration-confirmation#/start).
- An [HCP Terraform account](https://app.terraform.io/signup/account?utm_source=learn) with HCP Terraform [locally authenticated](/terraform/tutorials/cloud-get-started/cloud-login).
- An [HCP Terraform variable set configured with your AWS credentials](/terraform/tutorials/cloud-get-started/cloud-create-variable-set).

## Create example repository

Visit the [template
repository](https://github.com/hashicorp-education/learn-terraform-drift-and-policy)
for this tutorial. Click the **Use this template** button and select **Create a
New Repository**. Choose the GitHub owner that you use with HCP Terraform, and
name the new repository `learn-terraform-drift-and-policy`. Leave the rest of the
settings at their default values.

## Clone example configuration

Clone your example repository, replacing `USER` with your own GitHub username.
You will push to this fork later in the tutorial. 

```shell-session
$ git clone https://github.com/USER/learn-terraform-drift-and-policy.git
```

Change to the repository directory.

```shell-session
$ cd learn-terraform-drift-and-policy
```

## Review infrastructure configuration

This repository contains a local Terraform module that defines a network and
bastion host, and a root configuration that uses the module. It also contains
OPA policy definitions, which you will review later in this tutorial.

<CodeBlockConfig hideClipboard>

```shell-session
#FIXME: Update with final. Also, this is kind of a lot, probably simplify.
.
├── LICENSE
├── README.md
├── main.tf
├── modules
│   └── network
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
├── opa
│   ├── policies
│   │   ├── friday_deploys.rego
│   │   └── public_ingress.rego
│   └── policies.hcl
├── sentinel
│   ├── policies
│   │   ├── friday_deploys.sentinel
│   │   ├── mocks
│   │   │   ├── aws_security_groups_allowed.sentinel
│   │   │   └── aws_security_groups_forbidden.sentinel
│   │   ├── public_ingress.sentinel
│   │   └── test
│   │       ├── friday_deploys
│   │       │   ├── allowed_day.hcl
│   │       │   └── forbidden_day.hcl
│   │       └── public_ingress
│   │           ├── allowed_sgs.hcl
│   │           └── forbidden_sgs.hcl
│   └── policies.hcl
├── terraform.auto.tfvars
├── terraform.tf
└── variables.tf
```

</CodeBlockConfig>

Open the `modules/network/main.tf` file in your code editor. This configuration
uses the public `vpc` module to provision networking resources, including public
and private subnets and a NAT gateway. It then launches a bastion host in one of
the public subnets. 

<CodeBlockConfig hideClipboard filename="modules/network/main.tf">

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.13.0"

  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
}

resource "aws_security_group" "bastion" {
  name   = "bastion_ssh"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.80.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ec2_instance_type" "bastion" {
  instance_type = var.bastion_instance_type
}

resource "aws_instance" "bastion" {
  instance_type = var.bastion_instance_type
  ami           = data.aws_ami.amazon_linux.id

  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]

  lifecycle {
    precondition {
      condition     = data.aws_ec2_instance_type.bastion.default_cores <= 2
      error_message = "Change the value of bastion_instance_type to a type that has 2 or fewer cores to avoid over provisioning."
    }
  }
}
```

</CodeBlockConfig>

The bastion host is intended to be the single point of entry for any SSH traffic
to instances within the VPC’s private subnets. The configuration also includes a
security group that scopes any ingress SSH traffic to the bastion to just the
`192.80.0.0/16` CIDR block, a hypothetical CIDR representing your organization’s
network. 

Though this configuration references this module locally, in a larger
organization, you would likely publish it in your Terraform registry. By
including a bastion in the boilerplate of your networking configuration, you can
establish a standard for SSH access to instances in your networks. 

## Define a precondition

The `network` module defines a `bastion_instance_type` input variable to allow
users to account for anticipated usage and workloads. While you want to allow
users to specify an instance type, you do not want to allow them to provision an
instance that is too big. You will add a precondition to verify that the
instance type does not have more than 2 cores, to keep your operating costs low. 

First, add the data source below to the module configuration. It accesses the
instance type details, including the number of cores, from the AWS provider.

<CodeBlockConfig filename="modules/network/main.tf">

```hcl
data "aws_ec2_instance_type" "bastion" {
  instance_type = var.bastion_instance_type
}
```

</CodeBlockConfig>

Now, add the precondition to the `aws_instance.bastion` resource definition. 

<CodeBlockConfig hideClipboard filename="modules/network/main.tf" highlight="8-14">

```hcl
resource "aws_instance" "bastion" {
  instance_type = var.bastion_instance_type
  ami           = data.aws_ami.amazon_linux.id

  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]

  lifecycle {
    precondition {
      condition     = data.aws_ec2_instance_type.bastion.default_cores <= 2
      error_message = "Change the value of bastion_instance_type to a type that has 2 or fewer cores to avoid over provisioning."
    }
  }
}
```

</CodeBlockConfig>

Terraform evaluates preconditions when it plans your changes. In this case,
Terraform will load the `default_cores` value from the
`aws_ec2_instance_type.bastion` data source. Then, it will check whether the
configuration satisfies the condition before it will create the plan to
provision the bastion instance and your other resources.

## Deploy infrastructure

Navigate back to the root level of the repository directory. The root Terraform
configuration uses the `network` module to create a bastion host and networking
components including a VPC, subnets, a NAT gateway, and route tables. 

It sets the values for input variables in the `terraform.auto.tfvars` file. The
initial value for the bastion instance type is `t2.2xlarge`, which has 8 cores
and will fail the precondition as expected.

<CodeBlockConfig filename="terraform.auto.tfvars" hideClipboard>

```hcl
bastion_instance_type = "t2.2xlarge"
aws_region            = "us-east-2"
```

</CodeBlockConfig>

Set your HCP Terraform organization name as an environment variable to configure
your HCP Terraform integration.

```shell-session
$ export TF_CLOUD_ORGANIZATION=
```

<Tip>

 If multiple users in your HCP Terraform organization will run this tutorial,
 add a unique suffix to the workspace name in `terraform.tf`. 

</Tip>

Initialize your configuration. As part of initialization, Terraform creates your
`learn-terraform-drift-and-policy` HCP Terraform workspace.

```shell-session
$ terraform init
```

Now, attempt to plan your configuration. The plan will fail because the instance
size you specified is too big, and the precondition will return an error.

<Note>

This tutorial assumes that you are using a tutorial-specific HCP Terraform
organization with a global variable set of your AWS credentials. Review the
[Create a Credential Variable
Set](/terraform/tutorials/cloud-get-started/cloud-create-variable-set) for
detailed guidance. If you are using a scoped variable set, [assign it to your
new
workspace](/terraform/cloud-docs/workspaces/variables/managing-variables#apply-or-remove-variable-sets-from-inside-a-workspace)
now.

</Note>

```shell-session
$ terraform plan
Running plan in HCP Terraform. Output will stream here. Pressing Ctrl-C
will stop streaming the logs, but will not stop the plan running remotely.

Preparing the remote plan...

To view this run in a browser, visit:
https://app.terraform.io/app/your-org/learn-terraform-drift-and-policy/runs/run-uADaudsn745HtpAv

Waiting for the plan to start...

Terraform v1.8.3
on linux_amd64
Initializing plugins and modules...
module.network.data.aws_ami.amazon_linux: Refreshing...
module.network.data.aws_ec2_instance_type.bastion: Refreshing...
module.network.data.aws_availability_zones.available: Refreshing...
module.network.data.aws_ec2_instance_type.bastion: Refresh complete after 0s [id=t2.2xlarge]
module.network.data.aws_availability_zones.available: Refresh complete after 0s [id=us-east-2]
module.network.data.aws_ami.amazon_linux: Refresh complete after 0s [id=ami-02c4341ce4964ef28]
╷
│ Error: Resource precondition failed
│
│   on modules/network/main.tf line 67, in resource "aws_instance" "bastion":
│   67:       condition     = data.aws_ec2_instance_type.bastion.default_cores <= 2
│     ├────────────────
│     │ data.aws_ec2_instance_type.bastion.default_cores is 8
│
│ Change the value of bastion_instance_type to a type that has 2 or fewer
│ cores to avoid over provisioning.
╵
Operation failed: failed running terraform plan (exit 1)

─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't guarantee to take exactly these actions if you run "terraform apply" now.
```

The `t2.2xlarge` instance type has 8 cores, so this Terraform run failed the
precondition defined in the networking module. Overprovisioning the bastion
would incur unnecessary cost for your organization.

Change the `bastion_instance_type` variable in `terraform.auto.tfvars` to `t2.small`.

<CodeBlockConfig filename="terraform.auto.tfvars" highlight="1">

```hcl
bastion_instance_type = "t2.small"
aws_region            = "us-east-2"
```

</CodeBlockConfig>

Apply your configuration again. Respond `yes` to the prompt to confirm the operation.

```shell-session
$ terraform apply
Running apply in HCP Terraform. Output will stream here. Pressing Ctrl-C
will cancel the remote apply if it's still pending. If the apply started it
will stop streaming the logs, but will not stop the apply running remotely.

Preparing the remote apply...

To view this run in a browser, visit:
https://app.terraform.io/app/hashicorp-training/learn-terraform-drift-and-policy/runs/run-tCk6Da4HDNQdqQHT

Waiting for the plan to start...

Terraform v1.8.3
on linux_amd64
Initializing plugins and modules...
module.network.data.aws_ami.amazon_linux: Refreshing...
module.network.data.aws_availability_zones.available: Refreshing...
module.network.data.aws_ec2_instance_type.bastion: Refreshing...
module.network.data.aws_ec2_instance_type.bastion: Refresh complete after 0s [id=t2.small]
module.network.data.aws_availability_zones.available: Refresh complete after 0s [id=us-east-2]
module.network.data.aws_ami.amazon_linux: Refresh complete after 0s [id=ami-02c4341ce4964ef28]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.network.aws_instance.bastion will be created
  + resource "aws_instance" "bastion" {

## ...

Plan: 25 to add, 0 to change, 0 to destroy.

Do you want to perform these actions in workspace "learn-terraform-drift-and-policy"?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.network.module.vpc.aws_vpc.this[0]: Creating...
module.network.module.vpc.aws_vpc.this[0]: Still creating... [10s elapsed]
module.network.module.vpc.aws_vpc.this[0]: Creation complete after 11s [id=vpc-0c8dcf0e5d6c4da5b]

## ...

module.network.module.vpc.aws_nat_gateway.this[1]: Creation complete after 1m34s [id=nat-0b1a2fb0d660bf641]
module.network.module.vpc.aws_route.private_nat_gateway[1]: Creating...
module.network.module.vpc.aws_route.private_nat_gateway[0]: Creating...
module.network.module.vpc.aws_route.private_nat_gateway[0]: Creation complete after 1s [id=r-rtb-018b4e4a1e29501a41080289494]
module.network.module.vpc.aws_route.private_nat_gateway[1]: Creation complete after 1s [id=r-rtb-0ab827442f9e9d12f1080289494]

Apply complete! Resources: 25 added, 0 changed, 0 destroyed.
```

Using a precondition to verify resource allocation lets you use the most up to
date information from AWS to determine whether or not your configuration
satisfies the requirement. While you could have also used variable validation to
catch the violation, that would require researching all of the instance types
and their capacities and listing all of the acceptable instance types in your
configuration, making it less flexible.

## Review policy

Configuration-level validation such as variable constraints and preconditions
let you socialize standards from within your written configuration. However,
module authors and users must voluntarily comply with the standards. Module
authors must include conditions in module definitions, and users must consume
those modules to provision infrastructure. To enforce infrastructure standards
across entire workspaces or organizations, you can use HCP Terraform policies,
which work without requiring your users to write their infrastructure
configuration in a specific way. 

HCP Terraform allows you to choose either Sentinal or the Open Policy Agent
(OPA) as your policy engine. This tutorial includes policies for both policy
engines. Select the tab below to follow this tutorial with your preferred policy
engine.

<Tabs>

<Tab heading="Sentinel" group="sentinel">

Navigate to the `sentinel` directory in the example repository.

```shell-session
$ cd sentinel
```

Open the `policies.hcl` file to review the policy set configuration. 

<CodeBlockConfig filename="sentinel/policies.hcl" hideClipboard>

```hcl
policy "friday_deploys" {
  query = "data.terraform.policies.deployment_days.deny"
  enforcement_level = "advisory"
  params = {
    "forbidden_days" = ["friday"]
  }
}

policy "public_ingress" {
  query = "data.terraform.policies.public_ingress.deny"
  enforcement_level = "mandatory"
}
```

</CodeBlockConfig>

</Tab>

<Tab heading="Open Policy Agent" group="opa">

Navigate to the `opa` directory in the example repository.

```shell-session
$ cd opa
```

Open the `policies.hcl` file to review the policy set configuration. 

<CodeBlockConfig filename="opa/policies.hcl" hideClipboard>

```hcl
policy "friday_deploys" {
  query = "data.terraform.policies.deployment_days.deny"
  enforcement_level = "advisory"
  params = {
    "forbidden_days" = ["friday"]
  }
}

policy "public_ingress" {
  query = "data.terraform.policies.public_ingress.deny"
  enforcement_level = "mandatory"
}
```

</CodeBlockConfig>

</Tab>

</Tabs>

This policy set defines two policies, `friday_deploys` and `public_ingress`. It
sets the enforcement level to `advisory` for the `friday_deploys` policy, and to
`mandatory` for the `public_ingress` policy. When HCP Terraform detects a
failure in an advisory policy, it will notify you of the failures but allows you
to provision your resources anyway. When a mandatory policy fails, HCP Terraform
will refuse to apply the plan until the policy passes. The query format
references the package name declared in the policy file, and the name of the
rule defined for the policy.

In addition to placing guardrails on infrastructure configuration, you may wish
to enforce standards around your organization’s workflows themselves. One common
practice is to prevent infrastructure deployments on Fridays in order to lower
the risk of production incidents before the weekend. The `friday_deploys` policy
prevents infrastructure deployments on a certain day of the week. 

The example policies include tests, so that you can verify that they work as
expected before using them with HCP Terraform. Run your policy's tests now.

<Tab heading="Sentinel" group="sentinel">

Change into the `policies` directory.

```shell-session
$ cd policies
```

Next, run your tests.

```shell-session
$ sentinel test
PASS - deployment_days.sentinel
  PASS - test/deployment_days/allowed_day.hcl
  PASS - test/deployment_days/forbidden_day.hcl
PASS - public_ingress.sentinel
  PASS - test/public_ingress/allowed_sgs.hcl
  PASS - test/public_ingress/forbidden_sgs.hcl
2 tests completed in 10.661875ms
```

Sentinel loads tests from directories that match the name of each of your
policies.

Return to the `sentinel` directory.

```shell-session
$ cd ..
```

In the `policies.hcl` file, replace `friday` with the current day of the week
(e.g., `tuesday`) so you can observe how HCP Terraform will warn your when the
advisory policy fails this rule.

<CodeBlockConfig hideClipboard highlight="5" filename="sentinel/policies.hcl">

```hcl
policy "friday_deploys" {
  query = "data.terraform.policies.deployment_days.deny"
  enforcement_level = "advisory"
  params = {
    "forbidden_days" = ["tuesday"]
  }
}

policy "public_ingress" {
  query = "data.terraform.policies.public_ingress.deny"
  enforcement_level = "mandatory"
}
```

</CodeBlockConfig>

</Tab>

<Tab heading="Open Policy Agent" group="opa">

In the `policies.hcl` file, replace `friday` with the current day of the
week (e.g., `tuesday`) to test that the policy blocks deploys today. 

<CodeBlockConfig hideClipboard highlight="5" filename="opa/policies.hcl">

```hcl
policy "friday_deploys" {
  query = "data.terraform.policies.deployment_days.deny"
  enforcement_level = "advisory"
  params = {
    "forbidden_days" = ["tuesday"]
  }
}

policy "public_ingress" {
  query = "data.terraform.policies.public_ingress.deny"
  enforcement_level = "mandatory"
}
```

</CodeBlockConfig>

</Tab>

</Tabs>

The `public_ingress` policy parses the planned changes for a Terraform run and
checks whether they include security group updates that allows public ingress
traffic from all CIDRs (`0.0.0.0/0`). This policy helps enforce your security
posture by preventing the creation of any overly permissive security groups.  

<Tabs>

<Tab heading="Sentinel" group="sentinel">

<CodeBlockConfig hideClipboard filename="public_ingress.sentinel">

```sentinel
import "tfplan/v2" as tfplan

forbidden_ingress_cidrs = ["0.0.0.0/0"]

ingress_rules = filter tfplan.resource_changes as _, resource {
	resource.type is "aws_vpc_security_group_ingress_rule" and
		resource.change.actions is ["create"]
}

public_ingress = filter ingress_rules as _, ingress_rule {
  ingress_rule.change.after.cidr_ipv4 is "0.0.0.0/0"
}

main = rule {
  length(public_ingress) is 0
}
```

</CodeBlockConfig>

</Tab>

<Tab heading="Open Policy Agent" group="opa">

<CodeBlockConfig hideClipboard filename="public_ingress.rego">

```rego
import "tfplan/v2" as tfplan

forbidden_ingress_cidrs = ["0.0.0.0/0"]

ingress_rules = filter tfplan.resource_changes as _, resource {
	resource.type is "aws_vpc_security_group_ingress_rule" and
		resource.change.actions is ["create"]
}

public_ingress = filter ingress_rules as _, ingress_rule {
  ingress_rule.change.after.cidr_ipv4 is "0.0.0.0/0"
}

main = rule {
  length(public_ingress) is 0
}
```

</CodeBlockConfig>

</Tab>

</Tabs>

Stage your update to the `friday_deploys` policy and instance type precondition.

```shell-session
$ git add .
```

Commit the change.

```shell-session
$ git commit -m "Warn about deploys today."
```

Then, push your change.

```shell-session
$ git push
```

## Create a policy set

HCP Terraform organizes policies in policy sets. Policy sets can contain either
Sentinel or OPA policies. You can apply a policy set across an organization, or
only to specific workspaces. 

There are three ways to manage policy sets and their policies: VCS repositories,
the HCP Terraform API, or directly through the HCP Terraform UI. In this
tutorial, you will configure policy sets through VCS. The VCS workflow lets you
collaborate on and safely develop and version your OPA policies, establishing
the repository as the source of truth.

Create your policy set.

First, log in to [HCP Terraform](https://app.terraform.io/app), and select the
organization you will use to complete this tutorial.

Navigate to your organization's **Settings**, then to **Policy Sets**. Click
**Connect a new policy set**. 

Select the **Version control provider (VCS)** option.

<Tip>

 Review the [HCP Terraform VCS
 tutorial](/terraform/tutorials/cloud-get-started/cloud-vcs-change#enable-vcs-integration)
 for detailed guidance on how to configure your VCS integration.

</Tip>

On the **Configure settings** page:

* Select either **Sentinel** or **Open Policy Agent** as the policy integration,
  depending on which you are using for this tutorial.
* Name your policy `learn-terraform-drift-and-policy`.
* Set the scope of your policy set to **Policies enforced on selected projects and workspaces**.
* Under **Policy set source**, expand the **More options** drop down.
* Set the **Policies Path** to `sentinel` or `opa`.
* Set the **Scope of Policies** to **Policies enforced on selected workspaces**
* Under **Workspaces**, select your `learn-terraform-drift-and-policy` workspace. Then, click **Add workspace**.
* Under **Overrides**, uncheck the box next to "This policy set can be overridden in the event of mandatory failures."
* Click **Next**.

<Tip>

You can pin a policy set to a specific runtime version using the **Runtime version** drop-down. Policy runtime version management is currently in beta.

</Tip>

On the **Connect to VCS** page:

* Select your Github.com integration.
* Select the `learn-terraform-drift-and-policy` repository you created for this tutorial.
* Set the **Policies path** to either `/sentinel` or `/opa`, depending on which policy engine you are using for this tutorial.
* Click **Next**.

On the **Parameters** page:

* Click the **+ Add parameter** button.
* Set the **Key** to `forbidden_days` and the value to a list containing today, for example: `["monday"]`.
* Click the **Save parameter** button.
* Click the **Connect policy set** button to connect your policy set to HCP Terraform.

HCP Terraform will print out a summary of your new policy set.

## Trigger policy violation

The networking resources you provisioned earlier include a bastion host
configured with a security group that restricts ingress traffic to your
organization’s internal network. Imagine that an engineer is troubleshooting a
production incident and tries to get around this restriction by making the
security group more permissive.

To simulate this, update the ingress rule for the `aws_security_group.bastion`
resource in `modules/network/main.tf`. 

<CodeBlockConfig hideClipboard highlight="9" file="modules/network/main.tf">

```hcl
resource "aws_security_group" "bastion" {
  name   = "bastion_ssh"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

</CodeBlockConfig>

Navigate back to the repository's root directory.

```shell-session
$ cd ..
```

Run `terraform apply` to attempt to update the security group. 

```shell-session
$ terraform apply
Running apply in HCP Terraform. Output will stream here. Pressing Ctrl-C
will cancel the remote apply if it's still pending. If the apply started it
will stop streaming the logs, but will not stop the apply running remotely.

Preparing the remote apply...

To view this run in a browser, visit:
https://app.terraform.io/app/hashicorp-training/learn-terraform-drift-and-opa/runs/run-j3fNsPw1RvwPfJQ9

Waiting for the plan to start...

Terraform v1.4.0
on linux_amd64
Initializing plugins and modules...
##...
Post-plan Tasks:

OPA Policy Evaluation

→→ Overall Result: FAILED
 This result means that one or more OPA policies failed. More than likely, this was due to the discovery of violations by the main rule and other sub rules
2 policies evaluated

→ Policy set 1: learn-terraform-drift-and-policy-template (2)
  ↳ Policy name: friday_deploys
     | × Failed
     | No description available
  ↳ Policy name: public_ingress
     | × Failed
     | No description available
╷
│ Error: Task Stage failed.
```

HCP Terraform detected the policy failures: the security group allows public
ingress, and deploys are blocked today. The CLI output and run details in HCP
Terraform list which policies failed.

Using policies in HCP Terraform, you prevented Terraform from creating resources
that violate your infrastructure and organization standards.

Before moving on, fix your policy and configuration to allow a successful apply. 

First, update the `friday_deploys` policy to check for deployments on Fridays.
(If today is Friday, pick another day.)

<Tabs>

<Tab heading="Sentinel" group="sentinel">
<CodeBlockConfig hideClipboard highlight="4" filename="sentinel/sentinel.hcl">

```sentinel
policy "friday_deploys" {
  query = "data.terraform.policies.deployment_days.deny"
  enforcement_level = "advisory"
  params = {
    "forbidden_days" = ["friday"]
  }
}

policy "public_ingress" {
  query = "data.terraform.policies.public_ingress.deny"
  enforcement_level = "mandatory"
}
```

</CodeBlockConfig>

</Tab>

<Tab heading="OPA" group="opa">

</Tabs>

<CodeBlockConfig hideClipboard highlight="4" filename="friday_deploys.rego">

```rego
package terrafrom.policies.friday_deploys

deny[msg] {
  time.weekday(time.now_ns()) == "friday"

  msg := "No deployments allowed today."
}
```

</CodeBlockConfig>

Stage your update to the policy.

```shell-session
$ git add .
```

Commit the change.

```shell-session
$ git commit -m "Update policy"
```

Then, push your change.

```shell-session
$ git push
```

Revert the change to your for the `aws_security_group.bastion` resource in `modules/network/main.tf` so that it reflects your actual infrastructure configuration.

<CodeBlockConfig hideClipboard highlight="9" file="modules/network/main.tf">

```hcl
resource "aws_security_group" "bastion" {
  name   = "bastion_ssh"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.80.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

</CodeBlockConfig>

Reapply your configuration to bring your workspace back into a healthy state.

```shell-session
$ terraform apply
##...
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration and found no differences, so no
changes are needed.

Post-plan Tasks:

OPA Policy Evaluation

→→ Overall Result: PASSED
 This result means that all OPA policies passed and the protected behavior is allowed
2 policies evaluated

→ Policy set 1: learn-terraform-drift-and-opa-template (2)
  ↳ Policy name: friday_deploys
     | ✓ Passed
     | No description available
  ↳ Policy name: public_ingress
     | ✓ Passed
     | No description available
```


## Introduce infrastructure drift

<Note>

Drift detection is available in HCP Terraform **Plus** Edition. Skip to the
[clean up step](#clean-up-infrastructure) if you do not have access, or refer to
[HCP Terraform pricing](https://www.hashicorp.com/products/terraform/pricing)
for details.

</Note>

Custom conditions, input validation, and policy enforcement help organizations
maintain their standards at the time of resource provisioning. HCP Terraform can
also check whether existing resources in Terraform state still match the
intended configuration.

Returning to the hypothetical production incident, imagine that an engineer
tries to work around the policy by making manual resource changes while
troubleshooting. 

To simulate this, navigate to your [security groups in the AWS
console](https://us-east-2.console.aws.amazon.com/ec2/home?region=us-east-2#SecurityGroups). 

Find the `bastion_ssh` security group. Select the **Inbound rules** tab in the
security group details, then click **Edit inbound rules**. Delete the
`192.168.0.0/16` source CIDR and replace it with `0.0.0.0/0`. Then, click **Save
rules**.

You have now introduced infrastructure drift into your configuration by managing
the security group resource outside of the Terraform workflow.

## Detect drift

HCP Terraform’s automatic health assessments help make sure that existing
resources match their Terraform configuration. To do so, HCP Terraform runs
non-actionable, refresh-only plans in configured workspaces to compare the
actual settings of your infrastructure against the resources tracked in your
workspace’s state file. The assessments do not update your state or
infrastructure configuration.

Assessments include two types of checks, which you enable together. Drift
detection determines whether resources have changed outside of the Terraform
workflow. Health checks verify that any custom conditions you define in your
configuration are still valid, for example checking if a certificate is still
valid. You can enable assessments on specific workspaces, or across all
workspaces in an organization. Assessments only run on workspaces where the last
apply was successful. If the last apply failed, the workspace already needs
operator attention. Make sure your last apply succeeded before moving on.

Navigate to your `learn-terraform-drift-and-policy` workspace in the HCP
Terraform UI. Under the workspace's **Settings**, select **Health**.

Select **Enable**, then click **Save settings**.

Shortly after enabling health assessments, the first assessment runs on the
workspace. After the first assessment, following assessments run once every 24
hours.

After a few minutes, Terraform will report failed assessments on the workspace
overview page.

Click **View Details** to get more information. HCP Terraform detected the
change to your ingress rule and reported what will happen on your next run if
you do not update your configuration.

<Note>

Drift detection only reports on changes to the resource attributes defined in
your configuration. To avoid accidental drift, explicitly set any attributes
critical to your operations in your configuration, even if you rely on a
provider's default value for that attribute.

</Note>

The health assessments detected infrastructure drift. These checks ensure that
your infrastructure configuration still matches the written configuration and
satisfies any defined custom conditions, extending your validation coverage
beyond just the time of provisioning. Fixing drift is a manual process, because
you need to understand whether you want to keep the infrastructure changes made
outside of Terraform, or overwrite them. In this case, you could run another
Terraform apply to overwrite the security group update.

## Clean up infrastructure

Destroy the resources you created as part of this tutorial to avoid incurring
unnecessary costs. Respond `yes` to the prompt to confirm the operation.

```shell-session
$ terraform destroy
## FIXME
```

Optionally, delete your `learn-terraform-drift-and-policy` workspace and
policy set from your HCP Terraform organization.

## Next steps

In this tutorial, you used Terraform language features and HCP Terraform
policies to make sure that your infrastructure matches your configuration, and
complies with your organization’s needs and standards. Configuration-level
validation such as preconditions let you specify standards within Terraform
configurations. HCP Terraform policies let you enforce standards for an entire
workspace or organization. You also used HCP Terraform health assessments to
make sure that existing infrastructure still matched Terraform configuration,
and had not changed outside of the Terraform workflow.

To learn more about how Terraform features can help you validate your
infrastructure configuration, check out the following resources:

- Review the [policy documentation](/terraform/cloud-docs/policy-enforcement/opa).

- Learn how to [configure and use health assessments to detect infrastructure drift](/terraform/tutorials/cloud/drift-detection).

- Learn how to manage [your infrastructure costs in HCP Terraform](/terraform/tutorials/policy/cost-estimation).

- Learn how to use HCP Terraform run tasks and HCP Packer to [ensure machine image compliance](/terraform/tutorials/cloud/run-tasks-resource-image-validation).

- Review the [health assessment documentation](/terraform/cloud-docs/workspaces/health).

