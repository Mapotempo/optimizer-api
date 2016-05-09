# Mapotempo Optimizer API

Run an optimizer depending of problems contraints

## Installation

```
bundle
```


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
QUEUE=statused bundle exec rake resque:work
```

## Usage

The API is defined in Swagger format at
http://localhost:1791/swagger_doc
and can be tested with Swagger-UI
http://swagger.mapotempo.com/?url=http://optimizer.mapotempo.com/swagger_doc

```
curl -X POST --header "Content-Type:application/json" --data '{"vehicles":[]}' http://localhost:1791/0.1/vrp.json?api_key=key
```
