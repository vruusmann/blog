---
layout: post
title: "Tidying R's AdaBoost PMML documents"
author: vruusmann
--- 

The experience shows that the quality of PMML documents varies considerably across PMML producer software. One way to establish and enforce a well-defined quality level is to transform them to a canonicalized (aka "tidy") representation:

* Updating the PMML schema version.
* Translating deprecated and/or inefficient PMML constructs.
* Purging unused PMML constructs.
* Adding organization-specific extensions and metadata.
* Pretty-printing for improved readability and more meaningful diffing experience.

PMML operates with models and associated data flows at a fairly high abstraction level that is suitable for analysis and modification using programmatic agents. Every structural change can be verified and validated statically, so the risk of unforeseen side effects is minimal.

Therefore, the suggested line of thinking is that **if some PMML edit needs to be performed more than once, then it should be formalized as a programmatic agent**.

The Visitor API of the [JPMML-Model] (https://github.com/jpmml/jpmml-model) library constitutes a good platform for developing programmatic agents. There are already a number of Visitor classes available for addressing most common query and transformation needs. They can be used as-is, or combined with one another into new Visitor classes for addressing special needs.

### Workflow design ###

R's [`pmml` package] (http://cran.r-project.org/web/packages/pmml/) is one of the most popular PMML producer software. However, the quality of PMML documents varies dramatically between supported model types. Around the negative end of the spectrum is the support for AdaBoost models as implemented by the [`ada` package] (http://cran.r-project.org/web/packages/ada/).

This blog post is aimed at demonstrating a workflow for tidying AdaBoost PMML documents.

The exercise starts with training a binary classification model using the built-in ["soldat" dataset] (http://www.inside-r.org/packages/cran/ada/docs/soldat). The challenge is to predict whether a chemical compound is soluble or not based on its structure: `solubility = f(chemical structure)`. The data matrix has 5631 rows and 73 columns. The target column (ie. dependent variable) "y" is a categorical integer. Active columns (ie. independent variables) "x1", "x2", .., "x72" are continuous doubles.

``` r
library("ada")
library("pmml")

data("soldat")

set.seed(13)

ada = ada(y ~ ., data = soldat)
saveXML(pmml(ada), "ada.pmml")
```

When the resulting PMML document "ada.pmml" is opened in text editor, then the expert eye can spot the following shortcomings:

1. The model corresponds to a classification problem, but is encoded as a regression-type [`MiningModel` element] (http://dmg.org/pmml/v4-2-1/MultipleModels.html). This may confuse PMML consumers that employ different query and prediction workflows for different function types. For regression models, the query interface is typically no-op, and the prediction interface returns a single scalar value. Conversely, for classification models, the query interface exposes the universe of classes (eg. class labels and class descriptions), and the prediction interface returns the label of the winning class together with the class probability distribution. The AdaBoost PMML document aims to emulate the behaviour of conventional classification-type models, but does it rather poorly. For example, it completely lacks the the description of the target field (sic!), and class probabilities are calculated using the generic [`transformedValue` output feature] (http://dmg.org/pmml/v4-2-1/Output.html#ResFeat) rather than the special-purpose [`probability` output feature] (http://dmg.org/pmml/v4-2-1/Output.html#ResFeat).

2. The `functionName` attribute of member [`TreeModel` elements] (http://dmg.org/pmml/v4-2-1/TreeModel.html) has been specified as "regression", but their encoding is consistent with classification-type models instead. Again, this kind of false signalling may confuse standards-compliant PMML consumers.

3. Bloated [`MiningSchema` elements] (http://dmg.org/pmml/v4-2-1/MiningSchema.html). The idea of ensemble models is that every member model deals with a well-defined subspace of the input space. Unfortunately, the `pmml` package is incapable of filtering out irrelevant active fields, and populates all `MiningSchema` elements with exactly the same set of 72 [`MiningField` elements] (http://dmg.org/pmml/v4-2-1/MiningSchema.html). It isn't just a matter of style. For example, it prevents from conducting custom variable importance analyses using simple XQuery/XPath language queries.

4. Bloated predicate elements. By default, the `pmml` package encodes splits as [`CompoundPredicate` elements] (http://dmg.org/pmml/v4-2-1/TreeModel.html#xsdElement_CompoundPredicate), even though [`SimplePredicate` elements] (http://dmg.org/pmml/v4-2-1/TreeModel.html#xsdElement_SimplePredicate) would suffice. Digging deeper, there are problems with the `CompoundPredicate` element itself, because it does not convey the functional difference between the "main" split and "alternative" splits.

##### Step 1/3: Simplifying Predicate elements #####

The behaviour of the [`rpart()` function] (http://www.inside-r.org/packages/cran/rpart/docs/rpart), which underlies the [`ada()` function] (http://www.inside-r.org/packages/cran/ada/docs/ada), is controlled using options. The default configuration is aimed at being applicable to most diverse use cases. For example, it supports missing values in the training dataset, and generates a set of "alternative" splits in addition to the "main" split.

The default configuration is suboptimal for two reasons. First, the "soldat" dataset does not deal with missing values, which means that it is not necessary to consider and generate surrogate splits. Second, "alternative" splits could be useful during model training as they reflect the performance of individual active fields at the specified juncture (eg. a data scientist could use this information for steering her feature engineering efforts). However, they are completely useless during model deployment.

The options can be passed to the `ada()` function as an [`rpart.control` object] (http://www.inside-r.org/r-doc/rpart/rpart.control). Use `maxsurrogate = 0` and `maxcompete = 0` for disabling surrogate splits and "alternative" splits, respectively.

``` r
set.seed(13)

ada_compact = ada(y ~ ., data = soldat, control = rpart.control(maxsurrogate = 0, maxcompete = 0))
saveXML(pmml(ada_compact), "ada.pmml")
```

If the re-training is not an option (eg. dealing with legacy or third-party models), then exactly the same effect can be achieved using the Visitor API. The `pmml-rattle` module of the [JPMML-Evaluator] (https://github.com/jpmml/jpmml-evaluator) library provides Visitor class `org.jpmml.rattle.PredicateTransformer`, which implements two elementary transformations. First, the "unwrap" transformation (recursively-) replaces surrogate-type `CompoundPredicate` elements with their first child predicate element. Second, the "simplify" transform replaces single-value [`SimpleSetPredicate` elements] (http://dmg.org/pmml/v4-2-1/TreeModel.html#xsdElement_SimpleSetPredicate) with `SimplePredicate` elements.

Before transformation:

``` xml
<Node id="2" score="-1" recordCount="1496">
  <CompoundPredicate booleanOperator="surrogate">
    <SimplePredicate field="x38" operator="greaterOrEqual" value="52.8125"/>
    <SimplePredicate field="x39" operator="greaterOrEqual" value="35.8125"/>
    <SimplePredicate field="x37" operator="greaterOrEqual" value="79.4375"/>
    <SimplePredicate field="x40" operator="greaterOrEqual" value="27.5625"/>
    <SimplePredicate field="x41" operator="greaterOrEqual" value="19.5625"/>
    <SimplePredicate field="x42" operator="greaterOrEqual" value="14.8125"/>
  </CompoundPredicate>
  <ScoreDistribution value="-1" recordCount="0.209909429941401" confidence="0.86270149023613"/>
  <ScoreDistribution value="1" recordCount="0.055762741964127" confidence="0.13729850976387"/>
</Node>
```

The same after applying `org.jpmml.rattle.PredicateTransformer`:

``` xml
<Node id="2" score="-1" recordCount="1496">
  <SimplePredicate field="x38" operator="greaterOrEqual" value="52.8125"/>
  <ScoreDistribution value="-1" recordCount="0.209909429941401" confidence="0.86270149023613"/>
  <ScoreDistribution value="1" recordCount="0.055762741964127" confidence="0.13729850976387"/>
</Node>
```

##### Step 2/3: Purging unused MiningField elements #####

The JPMML-Model library provides several Visitor classes for performing static field analyses. First, Visitor class `org.jpmml.model.visitors.FieldReferenceFinder` can collect all field references inside the specified PMML class model fragment. Then, Visitor class `org.jpmml.model.visitors.FieldResolver` can map field references to actual `DataField`, `DerivedField` or `OutputField` elements. Finally, Visitor class `org.jpmml.model.visitors.FieldDependencyResolver` can (recursively-) expand individual `DerivedField` elements into their "constituent" `DataField` and `DerivedField` elements.

Visitor class `org.jpmml.model.visitors.MiningSchemaCleaner` combines all of the above functionality. The "clean" transformation first computes the optimal set of field references for the specified model element, and then rewrites its `MiningSchema` element by adding missing and/or removing redundant `MiningField` elements. This transformation is fully compliant with [PMML field scoping rules] (http://dmg.org/pmml/v4-2-1/FieldScope.html), and should be able to handle arbitrary complexity problems.

Before transformation:

``` xml
<MiningSchema>
  <MiningField name="x1"/>
  <MiningField name="x2"/>
  <!-- Omitted 69 field invocations "x3" through "x71" -->
  <MiningField name="x72"/>
</MiningSchema>
```

The same after applying `org.jpmml.model.visitors.MiningSchemaCleaner`:

``` xml
<MiningSchema>
  <MiningField name="x19"/>
  <MiningField name="x25"/>
  <MiningField name="x37"/>
  <MiningField name="x38"/>
  <MiningField name="x64"/>
  <MiningField name="x70"/>
  <MiningField name="x72"/>
</MiningSchema>
```

The cleaning of `MiningSchema` elements makes them processible with less sophisticated tools. For example, it will be possible to use simple XQuery/XPath language queries to compute custom variable importance metrics.

The relevance of an active field is proportional to the total number of `MiningField` elements that invoke it. Additionally, the role of an active field can be inferred from the relative location of invocations. The general rule with gradient boosting methods such as AdaBoost and GBM is that active fields that are more frequently referenced in earlier segments explain the "general case", whereas those that are more frequently referenced in later segments explain the "special case" (eg. outliers).

##### Step 3/3: Purging ScoreDistribution elements #####

The prediction of a `TreeModel` element is extracted from the winning `Node` element. For regression models, this is the value of the `score` attribute. For classification models, this is the class probability distribution as encoded by child `ScoreDistribution` elements.

It follows that AdaBoost PMML documents have no practical need for `ScoreDistribution` elements. The main argument against preserving existing elements is the drain on runtime resources. Grepping shows that `ScoreDistribution` elements outnumber `Node` elements two-to-one, which makes it the most numerous element type. This ratio keeps deteriorating when moving from binary-classification problems to multi-class classification problems.

The `pmml-rattle` module of the JPMML-Evaluator library provides Visitor class `org.jpmml.rattle.ScoreDistributionCleaner`, which cleans `Node` elements by nullifying the value of the `recordCount` attribute and removing all child `ScoreDistribution` elements.

Before transformation:

``` xml
<Node id="2" score="-1" recordCount="1496">
  <SimplePredicate field="x38" operator="greaterOrEqual" value="52.8125"/>
  <ScoreDistribution value="-1" recordCount="0.209909429941401" confidence="0.86270149023613"/>
  <ScoreDistribution value="1" recordCount="0.055762741964127" confidence="0.13729850976387"/>
</Node>
```

The same after applying `org.jpmml.rattle.ScoreDistributionCleaner`:

``` xml
<Node id="2" score="-1">
  <SimplePredicate field="x38" operator="greaterOrEqual" value="52.8125"/>
</Node>
```

The removal of `ScoreDistribution` elements can be easily undone. The idea is to score a dataset and capture the identifiers of winning Nodes using the [`entityId` output feature] (http://dmg.org/pmml/v4-2-1/Output.html#ResFeat).

### Workflow implementation ###

The JPMML-Model library provides an example command-line application `org.jpmml.model.CopyExample`, which reads a PMML schema version 3.X or 4.X document, applies a list of Visitor classes to the interim PMML class model object, and writes the result as a PMML schema version 4.2 document.

This application comes bundled with Visitor classes of the JPMML-Model library. The use of third-party Visitor classes is possible if their JAR file(s) have been appended to the application classpath. The following command performs the transformation of the PMML document "ada.pmml" to a new PMML document "ada-tidy.pmml" by applying a list of three transformers. It assumes that the snapshot versions of JPMML-Model and JPMML-Evaluator libraries are located in directories `jpmml-model` and `jpmml-evaluator`, respectively.

```
$ java -cp jpmml-model/pmml-model-example/target/example-1.2-SNAPSHOT.jar:jpmml-evaluator/pmml-rattle/target/pmml-rattle-1.2-SNAPSHOT.jar:jpmml-evaluator/pmml-evaluator-example/target/example-1.2-SNAPSHOT.jar org.jpmml.model.CopyExample --input ada.pmml --output ada-tidy.pmml --visitor-classes org.jpmml.rattle.PredicateTransformer,org.jpmml.model.visitors.MiningSchemaCleaner,org.jpmml.rattle.ScoreDistributionCleaner
```

The two PMML documents contain identical prediction logic. However, the transformed PMML document is nearly five times smaller (ie. 1'697 kB vs 352 kB), is much easier to read and maintain, and performs better.

A major hassle about XML documents is the formatting, especially the indent style. The [GlassFish Metro] (https://metro.java.net/) JAXB runtime (default for Oracle JDK/JRE) resets the indentation level after every eight columns, which makes deeply nested constructs such as decision trees hard to follow. The JVM can be instructed to activate a custom JAXB runtime by defining the `javax.xml.bind.context.factory` Java system property. For example, the [EclipseLink MOXy] (https://www.eclipse.org/eclipselink/) JAXB runtime is a good candidate as it keeps the indentation level intact.

```
$ java -Djavax.xml.bind.context.factory=org.eclipse.persistence.jaxb.JAXBContextFactory -cp jpmml-model/pmml-model-example/target/example-1.2-SNAPSHOT.jar org.jpmml.model.CopyExample ...
```