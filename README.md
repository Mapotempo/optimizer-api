# Mapotempo Optimizer API

Run an optimizer depending of contraints for a Vehicle Routing Problem (VRP).

## Prerequisite

* Ruby 2.2+ (RVM is recommanded)
```
sudo apt install ruby-full
```
* redis-server
```
sudo apt install redis-server
```
* libgeos-dev
```
sudo apt install libgeos-dev
```


## Installation

```
bundle install
```

This project requires some solver and interface projects in order to be fully functionnal !
* [Vroom actual master](https://github.com/VROOM-Project/vroom)
* [Optimizer-ortools](https://github.com/Mapotempo/optimizer-ortools) & [OR-tools v6.5](https://github.com/google/or-tools/tree/v6.5)
* (optional) [Optimizer-jsprit](https://github.com/Mapotempo/optimizer-jsprit) & [Jsprit](https://github.com/Mapotempo/jsprit)

## Configuration

Adjust config/environments files.


## Running

```
bundle exec rake server
```

And in production mode:
```
APP_ENV=production bundle exec rake server
```

Start Redis and then start the worker
```
APP_ENV=production COUNT=5 QUEUE=* bundle exec rake resque:workers
```

## Usage

The API is defined in Swagger format at
http://localhost:1791/swagger_doc
and can be tested with Swagger-UI
http://swagger.mapotempo.com/?url=http://optimizer.mapotempo.com/swagger_doc

```
curl -X POST --header "Content-Type:application/json" --data '{"vrp":{vehicles":[]}}' http://localhost:1791/0.1/vrp/submit.json?api_key=key
```

## Test

Run tests :
```
APP_ENV=test bundle exec rake test
```

You can add your own tests on specific Vehicle Routing Problem (for instance data from real cases). Let's see how to create a new test called "new_test".
You will find template for test in `test/real_cases_test.rb`

Before creating test, you need to capture scenario. Launch process with environment variable `DUMP_VRP` to record it:
```
DUMP_VRP=new_test bundle exec rake server
DUMP_VRP=new_test COUNT=5 QUEUE=* bundle exec rake resque:workers
```

Just run the original scenario to record it. Then two files are created in `test/fixtures` after running scenario:
- `new_test.json` file corresponding to original vrp sent by api
- `new_test.dump` file corresponding to complete vrp (for instance containing matrices if they are not provided in original vrp)

Now to create your test, just copy test template in `test/wrappers/real_cases_test.rb` with either `.json` or `.dump` depending on your data (e.g. if your vrp sent to api contains matrices you can use `.json` file, in other case use `.dump` file.)

If you create a test by using `.dump`, your test will fail as soon as vrp model is changed. Just run following task to update fixtures:
```
DUMP_VRP=my_test APP_ENV=test bundle exec rake test TEST=test/real_cases_test.rb
```
TODO: create a task to update all fixtures at once.

Note: you can update a test and run the modified scenario with new vrp `.json`:
```
bundle exec rake server
COUNT=5 QUEUE=* bundle exec rake resque:workers
curl -X POST --header "Content-Type:application/json" --data @test/fixtures/my_test.json http://localhost:1791/0.1/vrp/submit.json?api_key=key
```

If you don't want to run real cases tests you can deactive them:
```
SKIP_REAL_CASES=true APP_ENV=test bundle exec rake test
```
