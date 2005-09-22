<!-- Start "Book Review" -->

%# Only show this if we are on the first page
% unless ($burner->get_page) {
<h1><% $story->get_title %></h1>
<% $element->get_value('deck') %>
<hr />
% }

%# Display all the pages of this story
% $burner->display_pages('page');

<br>
Page <% $burner->get_page + 1 %>
<!-- End "Book Review" -->
<%publish>
if (my $media = $element->get_related_media) {
    $burner->publish_another($media);
}
</%publish>
