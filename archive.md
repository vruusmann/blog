---
layout: page
title: Archive
---

{% for post in site.posts %}
  * {{ post.date | date_to_string }} <span class="ni">&raquo;</span> [ {{ post.title }} ]({{ site.baseurl }}{{ post.url }})
{% endfor %}