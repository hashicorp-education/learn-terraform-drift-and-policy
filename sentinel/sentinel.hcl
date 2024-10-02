policy "friday_deploys" {
  source = "./policies/deployment_days.sentinel"
  enforcement_level = "advisory"
}

policy "public_ingress" {
  source = "./policies/public_ingress.sentinel"
  enforcement_level = "soft-mandatory"
}
