mock "time" {
  data = {
    now = {
      weekday_name  = "friday"
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
