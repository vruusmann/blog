---
layout: post
title: "JPMML-Evaluator: Upgrading from 1.0.X to 1.1.X"
author: vruusmann
---

Project timeline:

* 2009. Incubation. A PMML sub-project is started under the QsarDB project at Google Code.
* May 2011. Going public. The PMML sub-project becomes a top-level JPMML project at Google Code. The project is licensed under the BSD 3-Clause License. First public release 1.0.0.
* May 2013. The JPMML project is moved from Google Code to GitHub. Public releases from 1.0.1 to 1.0.22.
* February 2014. Going professional. The JPMML project is split into JPMML-Model and JPMML-Evaluator projects along responsibility lines. The license for the JPMML-Evaluator project is changed from BSD 3-Clause License to Affero GPL, version 3. Public releases 1.1.0 and onward.

The JPMML family of libraries uses a fairly common `<major>.<minor>.<release>` versioning scheme:

* Major. Public API level. The interface between the application code and the library.
* Minor. Private API level. The internal design of the library.
* Release. Feature level.

This versioning scheme is easy to exemplify on the basis of the JPMML-Evaluator library. The version 1 of the public API is designed around interfaces `org.jpmml.evaluator.Evaluator`, `org.jpmml.evaluator.Computable` and `org.jpmml.evaluator.ResultFeature` (and its subinterfaces). Versions 1.0 and 1.1 of the private API are very close. The differences are related to the way how classes and interfaces are named and organized into packages. Individual feature versions indicate the completeness and quality of the private API. Typically, a new feature version is released after one or two weeks of development effort.

The application code that relies on public API should be fairly robust towards private API and feature version upgrades. Here, it is worth pointing out that API evolution is performed in a non-defensive way. For example, when a public method is renamed or a public class is moved between packages, then the old location is simply cleared. This may cause occasional compiler errors, which are fairly easy to resolve when working with a capable Java IDE. In any case, all "breaking changes" are documented in release notes.

### Changes between JPMML 1.0.22 and JPMML-Model 1.1.0/JPMML-Evaluator 1.1.0 ###

##### Project layout #####

A project is a collection of library and support (e.g. code coverage, integration testing) modules. Projects are organized, built and deployed following Apache Maven conventions.

The split of the JPMML project into JPMML-Model and JPMML-Evaluator projects is depicted on the scheme below:
![Project structure] ({{ site.baseurl }}/assets/ProjectStructure.svg)

The two main changes are highlighted in yellow. First, the project artifact `org.jpmml:jpmml` was retired. It is superseded by two new project artifacts `org.jpmm:jpmml-model` and `org.jpmml:jpmml-evaluator`. Second, the license of the JPMML-Evaluator project (and all its modules) was changed from [BSD 3-Clause License] (http://opensource.org/licenses/BSD-3-Clause) to [Affero GPL, version 3.0] (http://www.gnu.org/licenses/agpl-3.0.html) (AGPLv3).

The technical side of the upgrade is straightforward. All module artifacts have retained their `groupId` and `artifactId` coordinates. Therefore, it is only a matter of setting the `version` coordinate to the desired value. For extra transparency, it may be wise to progress step by step, by upgrading first to the 1.1.0 version and then to the latest 1.1.X version. The success of each step should be verified by testing. For more information, please refer to the blog post about [testing PMML applications] ({{ site.baseurl }}{% post_url 2014-05-12-testing_pmml_applications %}).

In contrast, the legal side of the upgrade is much more complicated. AGPLv3 is a strong copyleft license that takes extreme stance on the matters of software freedom. Among other things, AGPLv3 requires that the works based on the JPMML-Evaluator library must also be licensed under AGPLv3 (or some other AGPLv3-compatible license). Unless a separate commercial license is obtained, this effectively prohibits incorporating the JPMML-Evaluator library into proprietary software or mixing it with other libraries that are released under AGPLv3-incompatible licenses.

##### Packaging #####

The Java code of the JPMML-Model library was re-packaged. The qualified name of the base package of every library module is now `org.jpmml.<name>`, where `name` is the name of the library module without the `pmml-` prefix. For example, the qualified names of the base packages of `pmml-schema` and `pmml-model` library modules are now `org.jpmml.schema` and `org.jpmml.model`, respectively.

The package `org.dmg.pmml` is reserved for the PMML class model. The majority of the Java code in this package is automatically generated after the underlying XML Schema Definition (XSD) file. There is only a limited number of manually crafted abstract classes and interfaces whose primary purpose is to enforce basic OOP design patterns (e.g. proper inheritance hierarchies).

Examples of classes that were moved between packages:

* `org.dmg.pmml.Version` → `org.jpmml.schema.Version`.
* `org.dmg.pmml.SourceLocationNullifier` → `org.jpmml.model.SourceLocationNullifier`
* `org.dmg.pmml.SourceLocationTransformer` → `org.jpmml.model.SourceLocationTransformer`
* `org.dmg.pmml.PMMLException` → `org.jpmml.manager.PMMLException`

This refactoring can be offset by updating the import statements of affected compilation units.

##### Marshalling and unmarshalling of PMML class model objects #####

The unmarshalling of a PMML class model object is the first step in any PMML consumption workflow. The JPMML-Model library provides a public utility class for most common use cases. However, application developers who need better control over unmarshalling options or who would like to perform custom pre- or post-processing operations may want to rely on their own implementation.

The main change between versions 1.0 and 1.1 of the private API is that the utility class `org.dmg.pmml.IOUtil` has been superseded by another utility class `org.jpmml.model.JAXBUtil`. As the name suggests, this class only deals with the Java Architecture for XML Binding (JAXB) side of things. The activities related to converting PMML documents between different PMML schema versions were extracted to special purpose Simple API for XML (SAX) filter classes.

Unmarshalling a PMML class model object using the version 1.0 of the private API:
{% highlight java %}
public PMML readPMML(InputStream is) throws Exception {
  return IOUtil.unmarshal(is);
}
{% endhighlight %}

Doing the same using the version 1.1 of the private API:
{% highlight java %}
public PMML readPMML(InputStream is) throws Exception {
  InputSource source = new InputSource(is);

  // Performs on-the-fly conversion from any PMML schema version document to the latest PMML schema version 4.2 document
  SAXSource filteredSource = ImportFilter.apply(source);

  return JAXBUtil.unmarshalPMML(filteredSource);
}
{% endhighlight %}

For more information about the import and export capabilities of the JPMML-Model library, please refer to the blog post about [converting PMML documents between different schema versions] ({{ site.baseurl }}{% post_url 2014-06-20-jpmml_model_api_import_export %}).

##### Miscellaneous #####

The public API of JPMML-Model and JPMML-Evaluator libraries is kept in sync with the latest PMML schema version in order to prevent terminological confusion.

The main change is that the method `org.jpmml.manager.Consumer#getPredictedFields()` was renamed to `#getTargetFields()`. It was triggered by the fact that starting from the PMML schema version 4.2, the usage type "predicted" is deprecated in favor of "target".

This refactoring can be offset by updating the affected method invocation expressions.

### Changes between JPMML-Model 1.1.2 and 1.1.3 ###

The annotation class `org.jpmml.schema.Schema` was split into annotation classes `org.jpmml.schema.Added` and `org.jpmml.schema.Removed`.

Declaring PMML schema version information using the version 1.0 of the private API:
{% highlight java %}
@Schema (
  min = Version.PMML_4_1
)
protected Boolean scorable;
{% endhighlight %}

Doing the same using the version 1.1 of the private API:
{% highlight java %}
@Added(Version.PMML_4_1)
protected Boolean scorable;
{% endhighlight %}

### Changes between JPMML-Evaluator 1.1.0 and 1.1.1 ###

The nested interface `org.jpmml.evaluator.FunctionUtil$Function` was moved to a top-level interface `org.jpmml.evaluator.Function`. Additionally, a package `org.jpmml.evaluator.functions` was created, and all nested classes implementing this interface were moved to top-level classes in that package. For example, the nested class `org.jpmml.evaluator.FunctionUtil$ArithmeticFunction` was moved to a top-level class `org.jpmml.evaluator.functions.ArithmeticFunction`.

The working set of PMML built-in functions and Java user-defined functions (UDF) is managed by the singleton class `org.jpmml.evaluator.FunctionRegistry`. An existing function can be looked up by its name using the method `#getFunction(String)`. A new function can be registered using the method `#putFunction(Function)`.

Defining and registering a Java user-defined function using the version 1.0 of the private API:
{% highlight java %}
FunctionUtil.Function echoFunction = new FunctionUtil.StringFunction(){

  @Override
  public String evaluate(String value){
    return value;
  }
};

FunctionUtil.putFunction("echo", echoFunction);
{% endhighlight %}

Doing the same using the version 1.1 of the private API:
{% highlight java %}
Function echoFunction = new StringFunction("echo"){

  @Override
  public String evaluate(String value){
    return value;
  }
};

FunctionRegistry.putFunction(echoFunction);
{% endhighlight %}