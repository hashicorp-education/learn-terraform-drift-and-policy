mock "tfplan/v2" {
  module {
    source = "../../mocks/aws_security_groups_forbidden.sentinel"
  }
}

test {
    rules = {
        main = true
    }
}
