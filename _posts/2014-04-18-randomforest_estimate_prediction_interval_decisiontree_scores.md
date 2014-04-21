---
layout: post
title: "Random forest intelligence. Part 2: Estimating the prediction interval based on member decision tree scores"
---

**Disclaimer**: ["prediction interval"] (http://en.wikipedia.org/wiki/Prediction_interval) is a well-defined concept in statistical inference. This blog post does not aim at such level of rigor. Here, "prediction interval" is more or less understood as "confidence interval of a prediction".

The exercise starts with training a regression-type random forest model for the ["Boston" dataset] (http://www.cs.toronto.edu/~delve/data/boston/bostonDetail.html). The newly trained random forest model is then used for prediction. It is specifically ordered to keep the predictions of all member decision tree models available for in-depth investigation (`predict.all = TRUE`). The scatter plot of experimental "medv" versus predicted "medv" indicates good statistical fit (see the figure below), but is otherwise rather uninformative. This figure changes dramatically for the better when data points are overlaid with error bars that represent one standard deviation of uncertainty. Due to the large number of data point some filtering is necessary. First, the yellow subset contains data points whose standard deviation is greater than 3 units and less than or equal to 5 units (total 80 observations). Second, the red subset contains data points whose standard deviation is greater than 5 units (total 30 observations).
{% highlight r %}
library("pmml")
library("randomForest")

data(Boston, package = "MASS")

boston.randomForest = randomForest(medv ~ ., Boston, ntree = 20)

saveXML(pmml(boston.randomForest), "RandomForestBoston.pmml")

boston.predict = predict(boston.randomForest, newdata = Boston, predict.all = TRUE)

boston.predict$sd = apply(boston.predict$individual, 1, FUN = sd)

drawErrorBars = function(x, y, sd, col){
	arrows(x, y - sd, x, y + sd, length = 0.05, angle = 90, code = 3, col = col)
}

plot(Boston$medv, boston.predict$aggregate, xlab = "medv", ylab = "Predicted medv")

yellowFilter = (boston.predict$sd > 3 & boston.predict$sd <= 5)
drawErrorBars(Boston$medv[yellowFilter], boston.predict$aggregate[yellowFilter], boston.predict$sd[yellowFilter], "yellow")

redFilter = (boston.predict$sd > 5)
drawErrorBars(Boston$medv[redFilter], boston.predict$aggregate[redFilter], boston.predict$sd[redFilter], "red")
{% endhighlight %}

Elevated standard deviation values indicate considerable variability among member decision tree scores. Higher variability is associated with less typical data points (i.e. prospective statistical outliers). First and foremost, the distribution of data points along the "medv" axis is rather uneven. Typical Boston properties fall into "medv" range from 15 to 25. They can be easily and reliably evaluated after their peers. It is interesting to note that all red error bars correspond to overestimation errors. More exclusive Boston properties fall into "medv" range 30 (35) and above. They are likely to possess distinguishing features, which makes it much more difficult to collect a representative set of peers for evaluation purposes. The majority of data points must be overlaid with yellow error bars. Again, it is interesting to note that red error bars correspond to underestimation errors. Boston properties that have "medv" value of 50.0 are known to represent a special case (censored values).
![medv vs. Predicted medv] ({{ site.baseurl }}/assets/RandomForestBoston.svg)

The resulting PMML document ["RandomForestBoston.pmml"] ({{ site.baseurl }}/assets/pmml/RandomForestBoston.pmml) can be opened in a text editor for inspection. The `MiningSchema` element contains 14 `MiningField` elements. The purpose of each `MiningField` element is indicated by its `usageType` attribute. Predicted fields specify usage type as "predicted". However, starting from the PMML schema version 4.2, the usage type "predicted" is deprecated in favor of "target".

The ["pmml" package] (http://cran.r-project.org/web/packages/pmml/index.html) for the R/Rattle environment has an odd habit of duplicating the predicted field as an output field. It creates an `Output` element and adds a single `OutputField` element to it. The value of the `name` attribute of such output fields is formulated by adding a prefix "Predicted\_" to the name of the predicted field.

The predicted field "medv" and the output field "Predicted\_medv" are identical from the PMML client application point of view. However, they are functionally different from the PMML consumer software point of view. The difference is related to the [scope of fields] (http://www.dmg.org/v4-2/FieldScope.html). Namely, it appears to be the case that predicted fields are not visible under the `Output` element. A predicted field can only be made visible by duplicating it as an output field. The PMML specification does not explicitly state a need for such "workaround", but it can be implied from the accompanying PMML examples.

Consider the following input record:
{% highlight json %}
{
 "crim" : 0.00632,
 "zn" : 18,
 "indus" : 2.31,
 "chas" : 0,
 "nox" : 0.538,
 "rm" : 6.575,
 "age" : 65.2,
 "dis" : 4.09,
 "rad" : 1,
 "tax" : 296,
 "ptratio" : 15.3,
 "black" : 396.9,
 "lstat" : 4.98
}
{% endhighlight %}

This input record evaluates to the following output record:
{% highlight json %}
{
 "medv" : 24.807583333333326,
 "Predicted_medv" : 24.807583333333326
}
{% endhighlight %}

The aggregation function can be deactivated by setting the `multipleModelMethod` attribute of the `Segmentation` element to "selectAll". It must be remembered that this approach only works with simple aggregation functions such as "average" and "majorityVote" where all member decision trees have equal weight (i.e. 1). The "selectAll" aggregation function produces a list of member decision tree scores. The data type of scores depends on the type of the random forest model. For classification- and clustering-type models this is typically `string`. For regression-type models this is typically `double`.

The output record now becomes:
{% highlight json %}
{
 "medv" : [24.32, 23.0, 24.1, 26.15, 24.0, 16.5, 23.98, 23.95, 25.96, 30.6, 23.975, 23.7333333333333, 31.42, 23.64, 29.5333333333333, 23.94, 24.0, 24.0, 24.9, 24.45], 
 "Predicted_medv" : [24.32, 23.0, 24.1, 26.15, 24.0, 16.5, 23.98, 23.95, 25.96, 30.6, 23.975, 23.7333333333333, 31.42, 23.64, 29.5333333333333, 23.94, 24.0, 24.0, 24.9, 24.45]
}
{% endhighlight %}

### Client application ###

The estimation of prediction intervals must be handled by custom application code. The PMML specification provides [aggregation transformations] (http://www.dmg.org/v4-2/Transformations.html#xsdElement_Aggregate), but they are not applicable to the current problem. First, the intended statistical procedure cannot be expressed in terms of primitive aggregations "count", "sum", "average", "min" and "max". Second, these primitive aggregations operate on lists of single-valued fields, not on single list-valued fields.

When the custom application code is implemented in Java, then it is possible to package it as a user-defined function and execute directly from within the [JPMML-Evaluator] (https://github.com/jpmml/jpmml-evaluator) library (or any other tool or service that incorporates it). User-defined functions are generally more elegant and easier to maintain than application code. The main drawback is that they are not directly portable between different PMML consumer software. For example, a PMML document that contains [JPMML-Evaluator] (https://github.com/jpmml/jpmml-evaluator) library specific features cannot be executed on [Zementis] (http://www.zementis.com) software (and vice versa). Undoubtedly, user-defined functions make an excellent investment when staying with a particular PMML consumer software long-term.

The PMML specification leaves the representation of complex field values open. The [JPMML-Evaluator] (https://github.com/jpmml/jpmml-evaluator) library represents list-valued field values using standard Java Collections Framework classes.

The following Java code iterates over all 20 values of the field "medv":
{% highlight java %}
Map<FieldName, ?> result = ...;

FieldName medv = new FieldName("medv");

// This unchecked cast is rather aggressive, but should be always good when dealing with regression-type models
Collection<? extends Number> values = (Collection<? extends Number>)result.get(medv);
for(Number value : values){
	System.out.println(value);
}
{% endhighlight %}

### Java-backed user-defined functions ###

Any class that implements interface `org.jpmml.evaluator.Function` qualifies as a user-defined function. It is recommended to extend an abstract class `org.jpmml.evaluator.functions.AbstractFunction` that provides utility methods for checking the number and data type of arguments, converting the result to proper data type etc.

Function invocation is handled by the `Apply` element. The `name` attribute identifies the function. PMML [built-in functions] (http://www.dmg.org/v4-2/BuiltinFunctions.html) employ simple text tokens as identifiers (e.g. arithmetic functions "+", "-", "*" and "/"). Java-backed user-defined functions should employ fully-qualified names of the function classes as identifiers (e.g. "com.mycompany.myproject.functions.SomeFunction"). This convention allows for very efficient mapping from function names to actual implementing classes. The [JPMML-Evaluator] (https://github.com/jpmml/jpmml-evaluator) library can dynamically locate and load Java-backed user-defined functions from JAR files that are part of the application classpath.

The [JPMML-Evaluator] (https://github.com/jpmml/jpmml-evaluator) library includes module "pmml-extension" that provides common user-defined functions [mean] (http://en.wikipedia.org/wiki/Mean) (class `org.jpmml.evaluator.functions.MeanFunction`), [standard deviation] (http://en.wikipedia.org/wiki/Standard_deviation) (class `org.jpmml.evaluator.functions.StandardDeviationFunction`) and [percentile] (http://en.wikipedia.org/wiki/Percentile) (class `org.jpmml.evaluator.functions.PercentileFunction`). Effectively, these user-defined function classes act as thin wrappers around the respective univariate statistic classes of the Apache [Commons Math] (http://commons.apache.org/proper/commons-math/) library. The latest ready to use module JAR file can be obtained from the [Maven Central repository] (http://repo1.maven.org/maven2/org/jpmml/pmml-extension/) (groupId `org.jpmml` and artifactId `pmml-extension`).

User-defined functions can be deployed by appending their JAR files (together with third-party dependency JAR files, if any) to the class path of the PMML consumer software. For example, the following command (Windows syntax) starts the [Openscoring REST web service] (https://github.com/jpmml/openscoring) and extends its "vocabulary of functions" with user-defined functions from module "pmml-extension":
{% highlight bash %}
java -cp "server-executable-1.1-SNAPSHOT.jar;pmml-extension-1.1.3.jar" org.openscoring.server.Main
{% endhighlight %}

##### Option 1: Normal distribution #####

The `Output` element after enhancement:
{% highlight xml %}
<Output>
 <!-- Omitted field "Predicted_medv" -->
 <OutputField name="Mean_medv" feature="transformedValue">
  <Apply function="org.jpmml.evaluator.functions.MeanFunction">
   <FieldRef field="Predicted_medv"/>
  </Apply>
 </OutputField>
 <OutputField name="SD_medv" feature="transformedValue">
  <Apply function="org.jpmml.evaluator.functions.StandardDeviationFunction">
   <FieldRef field="Predicted_medv"/>
   <Constant dataType="boolean">true</Constant>
  </Apply>
 </OutputField>
 <OutputField name="Conf95_medv_lower" feature="transformedValue">
  <Apply function="-">
   <FieldRef field="Mean_medv"/>
   <Apply function="*">
    <FieldRef field="SD_medv"/>
    <Constant>2</Constant>
   </Apply>
  </Apply>
 </OutputField>
 <OutputField name="Conf95_medv_upper" feature="transformedValue">
  <Apply function="+">
   <FieldRef field="Mean_medv"/>
   <Apply function="*">
    <FieldRef field="SD_medv"/>
    <Constant>2</Constant>
   </Apply>
  </Apply>
 </OutputField>
</Output>
{% endhighlight %}

The output record now becomes:
{% highlight json %}
{
 "Mean_medv" : 24.80758333333333,
 "SD_medv" : 3.1054891731232863,
 "Conf95_medv_lower" : 18.596604987086756,
 "Conf95_medv_upper" : 31.018561679579904
}
{% endhighlight %}

##### Option 2: Non-normal distribution #####

The `Output` element after enhancement:
{% highlight xml %}
<Output>
 <!-- Omitted field "Predicted_medv" -->
 <OutputField name="Quantile5_medv" feature="transformedValue">
  <Apply function="org.jpmml.evaluator.functions.PercentileFunction">
   <FieldRef field="Predicted_medv"/>
   <Constant>5</Constant>
  </Apply>
 </OutputField>
 <OutputField name="Quantile95_medv" feature="transformedValue">
  <Apply function="org.jpmml.evaluator.functions.PercentileFunction">
   <FieldRef field="Predicted_medv"/>
   <Constant>95</Constant>
  </Apply>
 </OutputField>
</Output>
{% endhighlight %}

The output record now becomes:
{% highlight json %}
{
 "Quantile5_medv" : 16.825,
 "Quantile95_medv" : 31.379
}
{% endhighlight %}
