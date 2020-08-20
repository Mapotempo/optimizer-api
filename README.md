# Mapotempo Optimizer API [![Build Status](https://travis-ci.com/Mapotempo/optimizer-api.svg?branch=master)](https://travis-ci.com/Mapotempo/optimizer-api)

Run an optimizer REST API depending of many contraints for a Vehicle Routing Problem (VRP).

## Prerequisite

For ruby, bundler and gems, rbenv or rvm are recommanded.

### On Ubuntu

* Ruby 2.5.5 (if not using rbenv/rvm)
```
sudo apt install ruby-full
```
* redis-server
```
sudo apt install redis-server
```
* libgeos-dev
```
sudo apt install libgeos-dev libgeos-3.7.1
```

* libicu-dev
```
sudo apt install libicu-dev
```

#### On Mac OS

```
brew install redis
brew install geos
```

## Installation

```
bundle install
```

This project requires some solver and interface projects in order to be fully functionnal!
* [Vroom actual master](https://github.com/VROOM-Project/vroom)
* [Optimizer-ortools](https://github.com/Mapotempo/optimizer-ortools) & [OR-tools v7.5](https://github.com/google/or-tools/releases/tag/v7.5)
* (optional / not supported anymore) [Optimizer-jsprit](https://github.com/Mapotempo/optimizer-jsprit) & [Jsprit](https://github.com/Mapotempo/jsprit)

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

Run tests:
```
APP_ENV=test bundle exec rake test
```

If you want to get information about how long each test lasts:
```
TIME=true HTML=true APP_ENV=test bundle exec rake test
```
This generates a report with test times. You can find the report in optimizer-api/test/html_reports folder.


You can add your own tests on specific Vehicle Routing Problem (for instance data from real cases). Let's see how to create a new test called "new_test".
You will find template for test in `test/real_cases_test.rb`

Before creating test, you need to capture scenario, in order to have a static image of your problem, insensitive to the routers edits.

Add your test JSON file into `test/fixtures/`. Now to create your test, just copy test template in `test/wrappers/real_cases_test.rb`, or any equivalent file.
Once launched, the dump file of the problem will be created and put aswell in `test/fixtures` as following:
- `new_test.dump` file corresponding to complete vrp with calculated matrices if not provided


If you create a test by using `.dump`, your test will fail as soon as vrp model is changed. Just run following task to update fixtures:
```
TEST_DUMP_VRP=true APP_ENV=test bundle exec rake test TEST=test/real_cases_test.rb
```

Note: you can update a test and run the modified scenario with new vrp `.json`:
```
bundle exec rake server
COUNT=5 QUEUE=* bundle exec rake resque:workers
curl -X POST --header "Content-Type:application/json" --data @test/fixtures/my_test.json http://localhost:1791/0.1/vrp/submit.json?api_key=key
```

If you don't want to run some long real cases tests you can deactive them:
```
SKIP_REAL_CASES=true APP_ENV=test bundle exec rake test
```
If you want to run a specific test file (let's say real_cases_scheduling_test.rb file only):
```
APP_ENV=test bundle exec rake test TEST=test/real_cases_scheduling_test.rb
```
If you want to run only one specific test (let's say test_instance_clustered test only) you can use focus or call:
```
APP_ENV=test bundle exec rake test TESTOPTS="--name=test_instance_clustered"
```

# Travis
To test on travis with a optimizer-ortools different than the latest version, specify in your travis configuration the following environment variable : OPTIMIZER_ORTOOLS_VERSION with you travis owner nick.
