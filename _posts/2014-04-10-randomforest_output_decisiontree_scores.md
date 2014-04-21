---
layout: post
title: "Random forest intelligence. Part 1: Outputting member decision tree scores"
---

A random forest model is a collection of decision tree models. The final prediction is computed by applying an aggregation function over member predictions. For classification- and clustering-type random forest models, this is typically a majority voting scheme, where the most frequent class label becomes the winner. For regression-type random forest models, this is typically the arithmetic mean. 

The PMML specification does not provide a special purpose element for the representation of random forest models, because they are regarded as a subtype of [multiple models] (http://www.dmg.org/v4-2/MultipleModels.html). The segmentation approach for the encoding of multiple models was introduced in PMML schema version 4.0. It follows that random forest models require PMML schema version 4.X compliant producer and consumer software to work. One of the most popular PMML producer software for random forest models is the ["pmml" package] (http://cran.r-project.org/web/packages/pmml/index.html) for the R/Rattle environment. It must be remembered that PMML production and consumption are completely separate functionalities. While the "pmml" package can store a `randomForest` data structure to PMML, it cannot (and probably never will) do the opposite, that is, load a `randomForest` data structure from PMML.

The current blog post details a method for interacting with member decision trees. This method is based on the `segmentId` attribute of the `OutputField` element. The `Output` element, which is simply a container of `OutputField` elements, is a "gatekeeper" that controls which computation results (and how) are exposed to the PMML client application. Getting to know this part of the PMML specification is crucial for PMML developers, because it gives access to some of the most powerful and versatile tools in the toolbox.

The exercise starts with training a classification-type random forest model for the ["iris" dataset] (http://archive.ics.uci.edu/ml/datasets/Iris). The "iris" dataset is rather small and well-behaving. A satisfactory discrimination between iris species can be achieved using a single decision tree model that is two levels deep. The idea of engaging a random forest algorithm is to try to "flatten" its structure. The following R script produces an ensemble of five decision tree models (`ntree = 5`), with every decision tree model being exactly one level deep (`maxnodes = 2`).
{% highlight r %}
library("pmml")
library("randomForest")

iris.randomForest = randomForest(Species ~ ., iris, ntree = 5, maxnodes = 2)

saveXML(pmml(iris.randomForest), "RandomForestIris.pmml")
{% endhighlight %}

The resulting PMML document ["RandomForestIris.pmml"] ({{ site.baseurl }}/assets/pmml/RandomForestIris.pmml) can be opened in a text editor for inspection. The core of the random forest model is the `Segmentation` element. It specifies the `multipleModelMethod` attribute as "majorityVote" and contains five `Segment` elements, one for each member decision tree. Individual `Segment` elements are identified by their `id` attribute. This attribute is optional according to the PMML specification. When the `id` attribute is missing, then the `Segment` element is identified by an implicit 1-based index.

The `Output` element contains four `OutputField` elements. The output first field "Predicted\_Species" is not that relevant as it simply generates a copy of the predicted value. The remaining three output fields "Probability\_setosa", "Probability\_versicolor" and "Probability\_virginica" compute the probabilities that the current input records belongs to the specified class.

Consider the following input record:
{% highlight json %}
{
 "Sepal.Length" : 5.1,
 "Sepal.Width" : 3.5,
 "Petal.Length" : 1.4,
 "Petal.Width" : 0.2
}
{% endhighlight %}

This input record evaluates the following output record:
{% highlight json %}
{
 "Species" : "setosa",
 "Predicted_Species" : "setosa",
 "Probability_setosa" : 0.8,
 "Probability_versicolor" : 0.2,
 "Probability_virginica" : 0.0
}
{% endhighlight %}

Multiplying the computed probabilities with the number of decision trees gives back the frequency of class labels. It is easy to see that this input record scored 4 times as "setosa", one time as "versicolor" and zero times as "virginica". However, it is impossible to find out which decision tree model exactly was the dissenter (i.e. predicted "versicolor" instead of "setosa") and what was the associated probability. Admittedly, this information is rarely needed in the production stage, but it may be a critical factor during development and testing stages.

The "debugging" work starts by declaring an `OutputField` element for every `Segment` element, and mapping the former to the latter using the `segmentId` attribute. When manipulating larger and more complex segmentation models on a regular basis then it will be probably worthwhile to develop custom tooling for this job. The [JPMML-Model] (https://github.com/jpmml/jpmml-model) library contains a command-line example application `org.jpmml.model.SegmentationOutputExample` for enhancing the `Output` element of segmentation models.

The `Output` element after the first enhancement round:
{% highlight xml %}
<Output>
 <!-- Omitted fields "Predicted_Species", "Probability_setosa", "Probability_versicolor" and "Probability_virginica" -->
 <OutputField name="tree_1" segmentId="1" feature="predictedValue"/>
 <OutputField name="tree_2" segmentId="2" feature="predictedValue"/>
 <OutputField name="tree_3" segmentId="3" feature="predictedValue"/>
 <OutputField name="tree_4" segmentId="4" feature="predictedValue"/>
 <OutputField name="tree_5" segmentId="5" feature="predictedValue"/>
</Output>
{% endhighlight %}

The output record now becomes:
{% highlight json %}
{
 "tree_1" : "setosa",
 "tree_2" : "setosa",
 "tree_3" : "setosa",
 "tree_4" : "versicolor",
 "tree_5" : "setosa"
}
{% endhighlight %}

The dissenter is the fourth decision tree. It stands out from the rest because it is hardwired to output either "versicolor" or "virginica".

Furher inspection of the random forest model reveals that the initial "flattening" idea has failed. There are four `Node` elements for "setosa", one for "versicolor" and five for "virginica". Therefore, this random forest model is unable to make successful predictions about the "versicolor" class, because the fourth decision tree will be always out-voted by two or more other decision trees.

By modifying the `feature` attribute of the `OutputField` element it is possible to get additional details about the specified member model. A member model may return one or more target fields. The selection of a target field is handled using the `targetField` attribute of the `OutputField` element. This attribute is required according to the PMML specification if there are two or more target fields. However, it is advisable to make it explicit even if there is only one target field.

The `Output` element after the second enhancement round:
{% highlight xml %}
<Output>
 <!-- Omitted fields "Predicted_Species", "Probability_setosa", "Probability_versicolor", "Probability_virginica", "tree_1", "tree_2", "tree_3", "tree_4" and "tree_5" -->
 <OutputField name="tree_4-nodeId" segmentId="4" targetField="Species" feature="entityId"/>
 <OutputField name="tree_4-Probability_setosa" segmentId="4" targetField="Species" feature="probability" value="setosa"/>
 <OutputField name="tree_4-Probability_versicolor" segmentId="4" targetField="Species" feature="probability" value="versicolor"/>
 <OutputField name="tree_4-Probability_virginica" segmentId="4" targetField="Species" feature="probability" value="virginica"/>
</Output>
{% endhighlight %}

The output record now becomes:
{% highlight json %}
{
 "tree_4-nodeId" : "2",
 "tree_4-Probability_setosa" : 0.0,
 "tree_4-Probability_versicolor" : 0.0,
 "tree_4-Probability_virginica" : 0.0
}
{% endhighlight %}

The node identifier may come in handy if the decision tree has more complex structure so that multiple `Node` elements have the same `score` attribute value. It may be the case that one particular `Node` element is known to represent a special condition (e.g. an outlier).

Currently, the fourth decision tree does not compute associated probabilities (i.e. the sum of "tree\_4-Probability\_*" fields is 0), because `Node` elements do not contain `ScoreDistribution` elements. This is a [known limitation] (http://stackoverflow.com/questions/21994430/r-pmml-class-distribution) of random forest models that are exported using the "pmml" package.