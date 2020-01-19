---
layout: post
title: "Converting R's random forest (RF) models to PMML documents"
author: vruusmann
---

The power and versatility of the R environment stems from its modular architecture. The functionality of the base platform can be quickly and easily expanded by downloading extension packages from the [CRAN repository](https://cran.r-project.org/). For example, random forest models can be trained using the following functions:

* `randomForest` ([`randomForest`](https://cran.r-project.org/package=randomForest) package). Generic regression and classification. This is the reference implementation.
* `cforest` ([`party`](https://cran.r-project.org/package=party) package). Generic regression and classification.
* `randomUniformForest` ([`randomUniformForest`](https://cran.r-project.org/package=randomUniformForest) package). Generic regression and classification.
* `bigrfc` ([`bigrf`](https://cran.r-project.org/package=bigrf) package). Generic classification.
* `logforest` ([`LogicForest`](https://cran.r-project.org/package=LogicForest) package). Binary classification.
* `obliqueRF` ([`obliqueRF`](https://cran.r-project.org/package=obliqueRF) package). Binary classification.
* `quantregForest` ([`quantregForest`](https://cran.r-project.org/package=quantregForest) package). Quantile regression.

Every function implements a variation of the "bagging of decision trees" idea. The result is returned as a random forest object, whose description is typically formalized using a package-specific S3 or S4 class definition.

All such model objects are dummy data structures. They can only be executed using a corresponding function `predict.<model_type>`. For example, a random forest object that was trained using the `randomForest` function can only be executed using the `predict.randomForest` function (and not with some other function such as `predict.cforest`, `predict.randomUniformForest` etc.).

This one-to-one correspondence between models and model execution functions makes the deployment of R models on Java and Python platforms very complicated. Basically, it will be necessary to implement a separate Java and Python executor for every model type.

![Executing R models on Java]({{ site.baseurl }}/assets/2015-02-24/R_Java.svg)

Predictive Model Markup Language (PMML) is an XML-based industry standard for the representation of predictive analytics workflows. PMML provides a [`MiningModel`](http://www.dmg.org/v4-3/MultipleModels.html) element that can encode a wide variety of bagging and boosting models (plus more complex model workflows). A model that has been converted to the PMML representation can be executed by any compliant PMML engine. A rather comprehensive list of PMML software can be found at Data Mining Group (DMG) website under the [PMML Powered](http://www.dmg.org/products.html) section.

PMML leads to simpler and more robust model deployment workflows. Basically, models are first converted from their function-specific R representation to the PMML representation, and then executed on a shared platform-specific PMML engine. For the Java platform this could be the [JPMML-Evaluator](https://github.com/jpmml/jpmml-evaluator) library. For the Python platform this could be [Augustus](augustus.googlecode.com) library.

![Executing R models as PMML on Java]({{ site.baseurl }}/assets/2015-02-24/R_PMML_Java.svg)

The conversion from R to PMML is straightforward, because these two languages share many of the core concepts. For example, they both regard data records as collections of key-value pairs (eg. individual fields are identified by name not by position), and decorate their data exchange interfaces (eg. model input and output data records) with data schema information.

### Conversion

The first version of the legacy [`pmml`](https://cran.r-project.org/package=pmml) package was released in early 2007. This package has provided great service for the community over the years. However, it has largely failed to respond to new trends and developments, such as the emergence and widespread adoption of ensemble methods.

This blog post is about introducing the [`r2pmml`](https://github.com/jpmml/r2pmml) package. Today, it simply addresses the major shortcomings of the legacy `pmml` package. Going forward, it aims to bring a completely new set of tools to the table. The long-term goal is to make R models together with associated data pre- and post-processing workflows easily transferable to other platforms.

The exercise starts with training a classification-type random forest model for the "audit" dataset. All the data preparation work has been isolated to a separate R script `audit.R`.

``` r
source("audit.R")

measure = function(fun){
  begin.time = proc.time()
  result = fun()
  end.time = proc.time();

  diff = (end.time - begin.time)
  print(paste("Operation completed in", round(diff[3] * 1000), "ms."))

  return (result)
}

audit = loadAuditData()
audit = na.omit(audit)

library("randomForest")

set.seed(42)
audit.rf = randomForest(Adjusted ~ ., data = audit, ntree = 100)
format(object.size(audit.rf), unit = "kB")

library("pmml")

audit.pmml = measure(function(){ pmml(audit.rf) })
format(object.size(audit.pmml), unit = "kB")
measure(function(){ saveXML(audit.pmml, "/tmp/audit-pmml.pmml") })

library("r2pmml")

measure(function(){ r2pmml(audit.rf, "/tmp/audit-r2pmml.pmml") })
measure(function(){ r2pmml(audit.rf, "/tmp/audit-r2pmml.pmml") })
```

The summary of the training run:

* Model training:
  * The size of the `audit.rf` object is 2'031 kB.
* Model conversion using the legacy `pmml` package:
  * The `pmml` function call is completed in 61'280 ms.
  * The size of the `audit.pmml` object is 280'058 kB.
  * The `saveXML` function call is completed in 33'926 ms.
  * The size of the XML-tidied `audit-pmml.pmml` file is 6'853 kB.
* Model conversion using the `r2pmml` package:
  * The first `r2pmml` function call is completed in 4'077 ms.
  * The second `r2pmml` function call is completed in 1'466 ms.
  * The size of the XML-tidied `audit-r2pmml.pmml` file is 6'106 kB.

##### pmml package

Typical usage:

``` r
library("pmml")

audit.pmml = pmml(audit.rf)
saveXML(audit.pmml, "/tmp/audit-pmml.pmml")
```

This package defines a conversion function `pmml.<model_type>` for every supported model type. However, in most cases, it is recommended to invoke the `pmml` function instead. This S3 generic function determines the type of the argument model object, and automatically selects the most appropriate conversion function.

When the `pmml` function is invoked using an unsupported model object, then the following error message is printed:

```
Error in UseMethod("pmml") :
  no applicable method for 'pmml' applied to an object of class "RandomForest"
```

The conversion produces an `XMLNode` object, which is a Document Object Model (DOM) representation of the PMML document. This object can be saved to a file using the `saveXML` function.

This package has hard time handling large model objects (eg. bagging and boosting models) for two reasons. First, all the processing takes place in R memory space. In this example, the memory usage of user objects grows more than hundred times, because the ~2 MB random forest object `audit.rf` gives rise to a ~280 MB DOM object `audit.pmml`. Moreover, all this memory is allocated incrementally in small fragments (ie. every new DOM node becomes a separate object), not in a large contiguous block. On a more positive note, it is possible that the (desktop-) GNU R implementation is outperformed in memory management aspects by alternative (server side-) R implementations.

Second, DOM is a low-level API, which is unsuitable for working with specific XML dialects such as PMML. Any proper medium- to high-level API should deliver much more compact representation of objects, plus take care of technical trivialities such as XML serialization and deserialization.

##### r2pmml package

Typical usage:

``` r
library("r2pmml")

r2pmml(audit.rf, "/tmp/audit-r2pmml.pmml")
```

The package defines a sole conversion function `r2pmml`, which is a thin wrapper around the Java converter application `org.jpmml.rexp.Main`. Behind the scenes, this function performs the following operations:

* Serializing the argument model object in ProtoBuf data format to a temporary file.
* Initializing the JPMML-R instance:
  * Setting the ProtoBuf input file to the temporary ProtoBuf file
  * Setting the PMML output file to the argument file
* Executing the JPMML-R instance.
* Cleaning up the temporary ProtoBuf file.

The capabilities of the `r2pmml` function (eg. the selection of supported model types) are completely defined by the capabilities of the [JPMML-R](https://github.com/jpmml/jpmml-r) library.

This package addresses the technical limitations of the legacy `pmml` package completely. First, all the processing (except for the serialization of the model object to a temporary file in the ProtoBuf data format) has been moved from the R memory space to a dedicated Java Virtual Machine (JVM) memory space. Second, model converter classes employ the [JPMML-Model](https://github.com/jpmml/jpmml-model) library, which delivers high efficiency without compromising on functionality. In this example, the ~2 MB random forest object `audit.rf` gives rise to a ~5.3 MB Java PMML class model object. That is 280 MB / 5.3 MB = ~50 times smaller than the DOM representation!

The detailed timing information about the conversion is very interesting (the readings correspond to the first and second `r2pmml` function call):

* The R side of operations:
  * Serializing the model in ProtoBuf data format to the temporary file: 1'262 and 1'007 ms.
* The Java side of operations:
  * Deserializing the model from the temporary file: 166 and 14 ms.
  * Converting the model from R representation to PMML representation: 648 and 310 ms.
  * Serializing the model in PMML data format to the output file: 2'001 and 135 ms.

The newly introduced `r2pmml` package fulfills all expectations by being 100 to 200 times faster than the legacy `pmml` package (eg. 310 vs. 61'280 ms. for model conversion, 135 vs. 33'926 ms. for model serialization). The gains are even higher when working with real-life random forest models that are order(s) of magnitude larger. Some gains are attributable to JVM warmup, because the conversion of ensemble models involves performing many repetitive tasks. The other gains are attributable to the smart caching of PMML content by the JPMML-R library, which lets the memory usage to scale sublinearly (with respect to the size and complexity of the model).

Also, the newly introduced `r2pmml` package is able to encode the same amount of information using fewer bytes than the legacy `pmml` package. In this example, if the resulting files `audit-r2pmml.pmml` and `audit-pmml.pmml` are XML-tidied following the same procedure, then it becomes apparent that the former is approximately 10% smaller than the latter (6'106 vs. 6'853 kB).

### Appendix

The `r2pmml` package depends on the [`RProtoBuf`](https://cran.r-project.org/package=RProtoBuf) package for ProtoBuf serialization and the [`rJava`](https://cran.r-project.org/package=rJava) package for Java invocation functionality. Both packages can be downloaded and installed from the CRAN repository using R's built-in function `install.packages`.

Here, the installation and configuration is played out on a blank GNU/Linux system (Fedora). All system-level dependencies are handled using the [Yum software package manager](https://fedoraproject.org/wiki/Yum).

##### RProtoBuf package

This package depends on [curl](https://curl.haxx.se/) and [protobuf](https://developers.google.com/protocol-buffers/) system libraries. It is worth mentioning that if the package is built from its source form (default behavior on *NIX systems), then all the required system libraries must be present both in their standard (no suffix) and development flavors (identified by the "-dev" or "-devel" suffix).

```
$ yum install curl curl-devel
$ yum install protobuf protobuf-devel
```

After that, the `RProtoBuf` package can be installed as usual:

``` r
install.packages("RProtoBuf")
```

If the system is missing the curl development library `curl-devel`, then the installation fails with the following error message:

```
checking for curl-config... no
Cannot find curl-config
ERROR: configuration failed for package ‘RCurl’
ERROR: dependency ‘RCurl’ is not available for package ‘RProtoBuf’
```

If the system is missing the protobuf development library `protobuf-devel`, then the installation fails with the following error message:

```
configure: error: ERROR: ProtoBuf headers required; use '-Iincludedir' in CXXFLAGS for unusual locations.
ERROR: configuration failed for package ‘RProtoBuf’
```

The format of ProtoBuf messages is defined by the proto file `inst/proto/rexp.proto`. Currently, the JPMML-R library uses the proto file that came with the RProtoBuf package version 0.4.2. As a word of caution, it will be useless to force the `r2pmml` package to depend on any RProtoBuf package version older than that, because this proto file underwent incompatible changes between versions 0.4.1 and 0.4.2. The Java converter application throws an exception (instance of `com.google.protobuf.InvalidProtocolBufferException`) when the contents of the ProtoBuf input file does not match the expected ProtoBuf message format.

The version of a package can be verified using the `packageVersion` function:

``` r
packageVersion("RProtoBuf")
```

##### rJava package

This package depends on Java version 1.7.0 or newer.

```
$ yum install java-1.7.0-openjdk
```

The Java executable `java` must be available via system and/or user path. Everything should be good to go if the java version can be verified by launching the Java executable with the `-version` option:

```
$ java -version
```

After that, the `rJava` package can be installed as usual:

``` r
install.packages("rJava")
```

### Resources

* R script: [`audit.R`]({{ site.baseurl }}/assets/2015-02-24/audit.R)