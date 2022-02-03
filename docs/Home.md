# About Optimizer API

Optimizer API provide a service to adress Rich Vehicle Routing Problems.
At this purpose it can call [multiple tools](#interfaced-tools) or method to provide a solution with the provided constraints. Moreover, some pretreatments, also called [interpreters](#interpreters) can be applied in order to complete the problem or split it.

## Capabilities
Using the denomination used by [Caceres-Cruz & al](https://dl.acm.org/citation.cfm?doid=2658850.2666003) the supported constraints are the following :

| Restriction | Code/Id |
| ----------- | ------- |
| Multiproducts | CP |
| Vehicle Capacity | C       |
| Homogeneous Fleet of Vehicles | FO |
| Heterogeneous Fleet of Vehicles | FE |
| Fixed Fleet of Vehicles | VF |
| Fixed Cost pet Vehicles | FC |
| Variable Cost of Vehicles | VC |
| Vehicle Site Dependance | DS |
| Vehicle Road Dependence *(router side)* | DR |
| Duration Constraints/Length | L |
| Driver Shifts/Workind Regulations *(partially)* | D |
| Balanced Routes *(partially)* | BR |
| Symmetric Cost Matrix | CS |
| Asymmetric Cost Matrix | CA |
| Intraroute Replenishments | IR |
| Time Windows | TW |
| Multiple Time Windows | MW |
| Pickup & Delivery | PD |
| Simultaneous Pickup & Delivery | PS |
| Multiple Visits | MV |
| Multiperiod/Periodic | MP |
| Multidepot | MD |
| Different End Locations/Open Routes | O |
| Different Start and End Locations | DA |
| Departure from Different Locations | DD |
| Precedence Constraints | PC |

& more...

## Data Model
The data model is constructed around a main object called **vrp** and is constituted of multiple high level entities

```json
"vrp": {
  "points": [],
  "vehicles": [],
  "units": [],
  "services": [],
  "shipments": [],
  "matrices": [],
  "rests": [],
  "relations": [],
  "zones": [],
  "configuration": {}
}
```
Those high level entities are completed by few others as **[Timewindows](Timewindow.md)** and **[Activities](Activity.md)** which are locally defined.
To define the model, the first step will be to describe every **[Point](Point.md)** which will be used in the description of the problem. This will include the depots and the customers locations.
Furthermore at least one **[Vehicle](Vehicle.md)** is mandatory and define at least one **[Service](Service-and-Shipment.md)** or **[Shipment](Service-and-Shipment.md)** will be essential to launch the solve.
The others entities are optional but may be mandatory regarding the problem to be adressed.

## Interfaced tools
### [OR-Tools](https://github.com/google/or-tools)
Google Optimization Tools (a.k.a., OR-Tools) is an open-source, fast and portable software suite for solving combinatorial optimization problems.

A wrapper has been developed to allow the call of the expected model and constraints : [Optimizer-Ortools](https://github.com/Mapotempo/optimizer-ortools)

### [VROOM](https://github.com/VROOM-Project/vroom)
VROOM is an open-source optimization engine written in C++14 that aim at providing good solutions to various real-life vehicle routing problems within a small computing time.

VROOM provide a direct exchange format in JSON

## [Resolution](Resolution.md)


## [Examples](Examples.md)

## Generate client
A client class could be generated using [swagger-codegen 2.4.12](https://github.com/swagger-api/swagger-codegen/tree/v2.4.12).
At this purpose, the current master and dev branches generates incorrect documentation.

The client can be generated using the following JSON:
[spec_file.json](https://gist.github.com/braktar/c1eeacbf1919f9fa3fe243768888bf9c)

To generate the associated Ruby gem:
```ruby
java -jar modules/swagger-codegen-cli/target/swagger-codegen-cli.jar generate -i spec_file.json -l ruby -o optimizer-client -DgemName=optimizer-client
```

This gives the following project:
[Optimizer-Client](https://github.com/braktar/optimizer-client)

Languages also available with swagger-codegen: 

ActionScript, Ada, Apex, Bash, C# (.net 2.0, 3.5 or later), C++ (cpprest, Qt5, Tizen), Clojure, Dart, Elixir, Elm, Eiffel, Erlang, Go, Groovy, Haskell (http-client, Servant), Java (Jersey1.x, Jersey2.x, OkHttp, Retrofit1.x, Retrofit2.x, Feign, RestTemplate, RESTEasy, Vertx, Google API Client Library for Java, Rest-assured), Kotlin, Lua, Node.js (ES5, ES6, AngularJS with Google Closure Compiler annotations) Objective-C, Perl, PHP, PowerShell, Python, R, Ruby, Rust (rust, rust-server), Scala (akka, http4s, swagger-async-httpclient), Swift (2.x, 3.x, 4.x, 5.x), Typescript (Angular1.x, Angular2.x, Fetch, jQuery, Node)
