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
