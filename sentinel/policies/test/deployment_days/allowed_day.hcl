mock "time" {
  data = {
    now = {
      day  = "monday"
      hour = 14
    }
  }
}

param "forbidden_days" {
  value = ["friday"]
}

test {
    rules = {
        main = true
    }
}
