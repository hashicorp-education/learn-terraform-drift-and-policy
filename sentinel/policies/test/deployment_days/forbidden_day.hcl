mock "time" {
  data = {
    now = {
      weekday  = "friday"
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
