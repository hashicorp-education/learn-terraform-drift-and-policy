mock "time" {
  data = {
    now = {
      day  = "friday"
      hour = 14
    }
  }
}

param "forbidden_days" {
  value = ["friday"]
}

test {
    rules = {
        main = false
    }
}
