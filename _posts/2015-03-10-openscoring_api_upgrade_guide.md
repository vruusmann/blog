---
layout: post
title: "Openscoring: Upgrading from 1.1.X to 1.2.X"
author: vruusmann
---

Openscoring version 1.1.X is an experimental solution in a sense that the majority of development took place in "ad hoc" mode.

Openscoring version 1.2.X is a thoughtful remake of the existing feature set. The goal is to make the REST API future proof by establishing (and expressly articulating) a solid foundation in terms of design principles and conventions.

The comparison of Openscoring versions 1.1.X and 1.2.X:

| Activity | Method | Version&nbsp;1.1&nbsp;endpoint | Version&nbsp;1.2&nbsp;endpoint | Data classes |
|---|---|---|---|---|
| Get&nbsp;all&nbsp;summaries | GET | `/model` | `/model` | Response changed from `List<ModelResponse>` to&nbsp;`BatchModelResponse` |
| Get&nbsp;all&nbsp;metric&nbsp;sets | GET | **`/model/metrics`** | **`/metric/model`** | (No changes) |
| Deploy | PUT | `/model/${id}` | `/model/${id}` | (No changes) |
| Download | GET | **`/model/${id}`** | **`/model/${id}/pmml`** | (No changes) |
| Get&nbsp;a&nbsp;summary | GET | **`/model/${id}/schema`** | **`/model/${id}`** | Response changed from `SchemaResponse` to&nbsp;`ModelResponse` |
| Get&nbsp;a&nbsp;metric&nbsp;set | GET | **`/model/${id}/metrics`** | **`/metric/model/${id}`** | (No changes)
| Evaluate data | POST | `/model/${id}` | `/model/${id}` | (No changes) |
| Evaluate data (batch mode) | POST | `/model/${id}/batch` | `/model/${id}/batch` | Request changed from `List<EvaluationRequest>` to&nbsp;`BatchEvaluationRequest`. Response changed from `List<EvaluationResponse>` to&nbsp;`BatchEvaluationResponse` |
| Evaluate data (CSV mode) | POST | `/model/${id}/csv` | `/model/${id}/csv` | (No changes) |
| Undeploy | DELETE | `/model/${id}` | `/model/${id}` | (No changes) |

### Endpoints ###

The URL of an endpoint consists of a model selector part and an optional feature selector part. The model selector is either the model collection `/model` or a model instance `/model/${id}`. The feature selector is the feature name `${feature}`.

| Activity | Version&nbsp;1.1 endpoint | Version&nbsp;1.2 endpoint |
|---|---|---|
| Feature applied to a model collection | `/model/${feature}` | `${feature}/model` |
| Feature applied to a model | `/model/${id}/${feature}` | `${feature}/model/${id}` |

The version 1.1 appends the feature selector to the model selector. This results in poor extensibility, because there exists a name collision between the endpoints `/model/${feature}` and `/model/${id}`. The workaround would be to treat feature names as reserved symbols. Unfortunately, this workaround does not "scale" very well in situations where the features are defined or modified dynamically.

Contrariwise, the version 1.2 prepends the feature selector to the model selector, which provides relief from name collisons. Obviously, it is still reasonable to treat "model" as a reserved symbol.

The case in point is the model metrics feature, which was remapped from the endpoints `/model/metrics` and `/model/${id}/metrics` to the endpoints `/metric/model` and `/metric/model/${id}`, respectively. By convention, REST resources are singular nouns.

A typical Openscoring workflow has the following steps:

1. Discover a model.
2. Load the data schema information of the selected model. Use this information to initialize bindings with data sources (active fields, group fields) and data sinks (target fields, output fields).
3. Evaluate the selected model with data records.

The version 1.1 is centered around PMML documents. For example, application clients use the same model instance endpoint `/model/${id}` to upload a PMML document using the PUT method, download it using the GET method and remove it using the DELETE method.

The version 1.2 is centered around the high-level description of a model. The contract for the model collection endpoint `/model` and the model instance endpoint `/model/${id}` has been unified. The former returns a `BatchModelResponse` object that contains an array of data schema-less `ModelResponse` objects. The latter returns a single data schema-full `ModelResponse` object.

Data schema information is stored as an optional Map-type field `schema`. Map keys are String constants `activeFields`, `groupFields`, `targetFields` and `outputFields`. Map values are arrays of `org.openscoring.common.Field` objects. Application clients can use this information for different value-added services such as generating smart data entry widgets (eg. a drop-down menu of categorical values instead of a textbox), performing data validation etc.

### Data classes ###

The version 1.2 imposes a new requirement that the client request and the server response must enclose one and only one JSON object. This requirement is reflected in the refactored Java class hierarchy, where all request classes inherit from the `org.openscoring.common.SimpleRequest` class, and all response classes inherit from the `org.openscoring.common.SimpleResponse` class.

Additionally, the JSON encoder is (re-)configured to emit only non-null and non-empty fields. For example, the JSON representation of an object does not include String fields that are either uninitialized (ie. `null`) or initialized with an empty String value (ie. `""`). This change was necessary to make the narrowing reference conversion safe on request and response objects.

The `SimpleResponse` class declares a sole String-type field `message`, which is initialized with an appropriate error message if the operation fails because of an error condition. This message is suitable for displaying to end users. Application clients can put it into context by paying attention to the HTTP status code. For example, HTTP status codes 4XX indicate a permanent failure due to client-side problem (eg. missing or invalid input data). HTTP status codes 5XX indicate temporary failure due to server-side problem (eg. lack of resources).

Java application clients can employ the following idiom to check the outcome of an operation:

``` java
public <R extends SimpleResponse> void checkResponse(R response){
  String message = response.getMessage();

  // The error condition is encoded by initializing the "message" field and leaving all other fields uninitialized
  if(message != null){
    throw new RuntimeException(message);
  }
}
```

The version 1.1 does not handle error conditions. Both checked and unchecked exceptions are allowed to "bubble up" to the web container, which formats them as HTML error pages. This makes the life of application developers miserable, because they need to be ready to handle different data formats from the same endpoint (ie. JSON for a successful operation, web container-specific HTML for a failed operation).

The version 1.2 does its best to handle all internal and external error conditions. For example, if the client refers to a non-existent model instance `FictionalId`, then the JAX-RS exception object (instance of class `javax.ws.rs.NotFoundException`) is converted to the following `SimpleResponse` object:

``` json
{
  "message" : "Model \"FictionalId\" not found"
}
```

The version 1.1 specifies several endpoints that either accept an array of JSON objects as an argument, or return an array of JSON objects as a result. For example, the batch data evaluation endpoint `/model/${id}/batch` expects the request body to contain an array of `EvaluationRequest` objects:

``` json
[
  {
    "id" : "record-1",
    "arguments" : { }
  },
  {
    "id" : "record-2",
    "arguments" : { }
  }
]
```

The version 1.2 does not allow such behaviour, because a JSON array cannot be coerced to a `SimpleResponse` object in case of an error condition. The solution is to place a JSON array into an "envelope" JSON object. By convention, the name of the envelope class is derived by prepending "Batch" to the name of the array element class.

The `BatchEvaluationRequest` class holds the array of `EvaluationRequest` objects as a List-type field `requests`. Application clients can keep track of parallel or asynchronous requests by initializing the String-type field `id` with a unique value.

The request body now becomes:

``` json
{
  "id" : "batch-1",
  "requests" : [
    {
      "id" : "record-1",
      "arguments" : { }
    },
    {
      "id" : "record-2",
      "arguments" : { }
    }
  ]
}
```

### Application ###

The version 1.2 delivers an all-new JAX-RS application class `org.openscoring.service.Openscoring`.

Application configuration is handled using the [Typesafe Config](https://github.com/typesafehub/config) library. The default configuration is located in file `openscoring-service/src/main/resources/reference.conf`. This file encodes configuration entries as key-value pairs in the HOCON data format, which is a human-oriented superset of the JSON data format (eg. allows comments, allows the omission of unnecessary punctuation symbols). By convention, configuration entries are arranged into a two-level hierarchy, where the top level points to a Java class name and the bottom level to a field name. For example, the configuration entry `modelRegistry.visitorClasses` targets the field `visitorClazzes` of the `org.openscoring.service.ModelRegistry` class.

The default configuration can be overriden (either in full or in parts) by user-specified configuration file.

The configuration entry `application.componentClasses` (formerly a command-line option `--component-classes`) specifies a list of JAX-RS component classes. If there is a need to customize or extend the functionality of the Openscoring web service in any way, then it should be achieved by developing a dedicated JAX-RS component class using the [Jersey](https://jersey.java.net/) library.

For example, a company-specific client authentication and authorization could be implemented as a JAX-RS filter class `com.mycompany.service.MySecurityContextFilter`. This class can be plugged in (and the default class `org.openscoring.service.NetworkSecurityContextFilter` plugged out) by updating the configuration entry `application.componentClasses` as follows:

```
application {
  // List of JAX-RS Component class names that must be registered
  componentClasses = [
    "com.mycompany.service.MySecurityContextFilter"
  ]
}
```

The configuration entry `modelRegistry.visitorClasses` (formerly a command-line option `--visitor-classes`) specifies a list of Visitor classes. Newer versions of [JPMML-Model](https://github.com/jpmml/jpmml-model) and [JPMML-Evaluator](https://github.com/jpmml/jpmml-evaluator) libraries contain packages `org.jpmml.model.visitors` and `org.jpmml.evaluator.visitors`, respectively, which provide Visitor classes for optimizing the PMML class model object for better performance.

The version 1.2 packages the JAX-RS application in two flavours:

* Web application (module `openscoring-webapp`). The web application conforms to the Java Servlet 2.5 specification. The WAR file can be deployed on all popular Java web containers (eg. Jetty, Tomcat, Grizzly) without modification.
* Command-line application (module `openscoring-server`). The executable uber-JAR file embeds the latest stable [Jetty](https://eclipse.org/jetty/) web container, which is known for its robustness and excellent performance characteristics. The command-line application is equally fit for quick experimentation and for serious production use.

The version 1.2 command-line application does not support the majority of "old" command-line options. Some of them were converted to configuration entries as demonstrated above. The others were extracted into new applications.

The case in point is the command-line option `--deploy-dir`, which was extracted to a command-line application `org.openscoring.client.DirectoryDeployer`. Such "separation of concerns" makes it possible to synchronize a local filesystem directory with a remote Openscoring web service, or monitor several directories for PMML file addition and removal events simultaneously.
