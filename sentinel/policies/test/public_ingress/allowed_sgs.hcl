mock "tfplan/v2" {
  module {
    source = "../../mocks/aws_security_groups_allowed.sentinel"
  }
}

test {
    rules = {
        main = true
    }
}
