package Bric::App::Callback::ContainerProf;

use base qw(Bric::App::Callback);
__PACKAGE__->register_subclass;
use constant CLASS_KEY => 'container_prof';

use strict;
use Bric::Config qw(:time);
use Bric::App::Authz qw(:all);
use Bric::App::Session qw(:state);
use Bric::App::Util qw(:msg :aref :history :wf);
use Bric::App::Event qw(log_event);
use Bric::App::Callback::Desk;
use Bric::App::Callback::Profile::Media;
use Bric::Biz::ElementType;
use Bric::Biz::ElementType::Parts::FieldType;
use Bric::Biz::Element::Container;
use Bric::Biz::Element::Field;
use Bric::Util::Fault qw(:all);
use Bric::Util::Trans::FS;
use Bric::Biz::Workflow qw(:wf_const);
eval { require Text::Levenshtein };
require Text::Soundex if $@;

my $STORY_URL  = '/workflow/profile/story';
my $CONT_URL   = '/workflow/profile/story/container';
my $MEDIA_URL  = '/workflow/profile/media';
my $MEDIA_CONT = '/workflow/profile/media/container';

my $regex = {
    "\n"   => qr/\s*\n\n|\r\r\s*/,
    '<p>'  => qr/\s*<p>\s*/,
    '<br>' => qr/\s*<br>\s*/,
};

my %pkgs = (
    story => 'Bric::Biz::Asset::Business::Story',
    media => 'Bric::Biz::Asset::Business::Media',
);

sub edit : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $r = $self->apache_req;

    my $element = get_state_data($self->class_key, 'element');

    # Update the existing fields and get the child element matching ID
    my $edit_element = $self->_update_parts($param);

    # Push this child element on top of the stack
    $self->_push_element_stack($edit_element);

    # Don't redirect if we're already on the right page.
    if ($element->get_object_type eq 'media') {
        unless ($r->uri eq "$MEDIA_CONT/edit.html") {
            $self->set_redirect("$MEDIA_CONT/edit.html");
        }
    } else {
        unless ($r->uri eq "$CONT_URL/edit.html") {
            $self->set_redirect("$CONT_URL/edit.html");
        }
    }
}

sub bulk_edit : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $r = $self->apache_req;

    my $element = get_state_data($self->class_key, 'element');
    my $edit_element = $self->_update_parts($param);

    # Push the current element onto the stack.
    $self->_push_element_stack($edit_element);
    set_state_data($self->class_key, 'view_flip', 0);

    my $uri  = $element->get_object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
    $self->set_redirect("$uri/edit_bulk.html");
}

sub view : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $r = $self->apache_req;
    my $field = $self->trigger_key;

    my $element = get_state_data($self->class_key, 'element');
    my $element_id = $self->value;
    my ($view_element) = grep(($_->get_id == $element_id), $element->get_containers);

    # Push this child element on top of the stack
    $self->_push_element_stack($view_element);

    if ($element->get_object_type eq 'media') {
        $self->set_redirect("$MEDIA_CONT/") unless $r->uri eq "$MEDIA_CONT/";
    } else {
        $self->set_redirect("$CONT_URL/") unless $r->uri eq "$CONT_URL/";
    }
}

sub reorder : Callback {
    # don't do anything, handled by the update_parts code now
}

sub delete : Callback {
    # don't do anything, handled by the update_parts code now
}

sub clear : Callback(priority => 1) {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    clear_state($self->class_key);
}

sub add_element : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $r = $self->apache_req;

    # get the element
    my $element = get_state_data($self->class_key, 'element');
    my $key = $element->get_object_type();
    # Get this element's asset object if it's a top-level asset.
    my $a_obj;
    if ($element->get_element_type()->get_top_level()) {
        $a_obj = $pkgs{$key}->lookup({id => $element->get_object_instance_id()});
    }
    my $fields = mk_aref($self->params->{$self->class_key . '|add_element'});

    foreach my $f (@$fields) {
        my ($type,$id) = unpack('A5 A*', $f);
        my $at;
        if ($type eq 'cont_') {
            $at = Bric::Biz::ElementType->lookup({id=>$id});
            my $cont = $element->add_container($at);
            $element->save();
            $self->_push_element_stack($cont);

            if ($key eq 'story') {
                # Don't redirect if we're already at the edit page.
                $self->set_redirect("$CONT_URL/edit.html")
                  unless $r->uri eq "$CONT_URL/edit.html";
            } else {
                $self->set_redirect("$MEDIA_CONT/edit.html")
                  unless $r->uri eq "$MEDIA_CONT/edit.html";
            }

        } elsif ($type eq 'data_') {
            $at = Bric::Biz::ElementType::Parts::FieldType->lookup({id=>$id});
            $element->add_field($at);
            $element->save();
            set_state_data($self->class_key, 'element', $element);
        }
        log_event($key.'_add_element', $a_obj, {Element => $at->get_key_name})
          if $a_obj;
    }
}

sub update : Callback(priority => 1) {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    my $widget = $self->class_key;
    return if $param->{'_inconsistent_state_'} || $param->{"$widget|up_cb"};

    $self->_update_parts($self->params);

    # Don't save the element; that's handled by the callback for the button
    # that was actually clicked (e.g., "Save")--or not (e.g., "Cancel"), as
    # the case may be.
#    my $element = get_state_data($self->class_key, 'element');
#    $element->save;
}

sub pick_related_media : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $element = get_state_data($self->class_key, 'element');
    my $object_type = $element->get_object_type();
    my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
    $self->set_redirect("$uri/edit_related_media.html");
}

sub create_related_media : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $widget = $self->class_key;

    # Get a handle on things to restore later.
    my $element =  get_state_data($widget, 'element');
    my $type    = $element->get_object_type;
    my $asset   = get_state_data($type.'_prof', $type);
    my $state   = get_state($widget);
    my $type_state = get_state_name($type.'_prof');
    clear_state($widget);

    my $param = $self->params;
    return if $param->{_inconsistent_state_};
    return unless $param->{"$widget|file"};

    # Get the workflow for media files.
    my $media_wf = find_workflow($asset->get_site_id, MEDIA_WORKFLOW, READ);
    unless (find_desk($media_wf, CREATE)) {
        add_msg("You do not have sufficient permission to create a media "
                . "document for this site");
        return;
    }

    my $wf_id = $media_wf->get_id;
    set_state_data('media_prof', 'work_id', $wf_id);

    # Set up the parameters to create a new media document.
    my $agent = $ENV{HTTP_USER_AGENT};
    my $filename = $agent =~ /windows/i && $agent =~ /msie/i
        ? Bric::Util::Trans::FS->base_name($param->{"$widget|file"}, 'win32')
        : $param->{"$widget|file"};
    my $m_param = {
        'title'                   => $filename,
        'cover_date'              => $asset->get_cover_date(ISO_8601_FORMAT),
        'priority'                => $asset->get_priority,
        'media_prof|category__id' => $asset->get_primary_category->get_id,
        'media_prof|source__id'   => $asset->get_source__id,
        'media_prof|at_id'        => $param->{'media_prof|at_id'},
        'media_prof|file'         => $param->{"$widget|file"},
        'file_field_name'         => "$widget|file",
    };

    my $media_cb = Bric::App::Callback::Profile::Media->new(
        cb_request => $self->cb_request,
        pkg_key    => 'media_prof',
        apache_req => $self->apache_req,
        params     => $m_param
    );

    $media_cb->create;
    $media_cb->update;
    my $media = get_state_data('media_prof', 'media');
    my $mid = $media->get_id;
    $element->set_related_media($mid);

    # Set up the original state for returning from the media profile.
    $media_cb->save_and_stay(1);
    set_state_data(_profile_return => {
        state      => $state,
        type_state => $type_state,
        prof       => $asset,
        type       => $type,
        uri        => $self->apache_req->uri,
    });
    # Edit the new media document.
    $self->set_redirect("/workflow/profile/media/new/$wf_id/$mid/");
}

sub relate_media : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $element = get_state_data($self->class_key, 'element');
    $element->set_related_media($self->value);
    $self->_handle_related_up;
}

sub unrelate_media : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $element = get_state_data($self->class_key, 'element');
    $element->set_related_media(undef);
    $self->_handle_related_up;
}

sub pick_related_story : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $element = get_state_data($self->class_key, 'element');
    my $object_type = $element->get_object_type();
    my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
    $self->set_redirect("$uri/edit_related_story.html");
}

sub relate_story : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $element = get_state_data($self->class_key, 'element');
    $element->set_related_story($self->value);
    $self->_handle_related_up;
}

sub unrelate_story : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $element = get_state_data($self->class_key, 'element');
    $element->set_related_story(undef);
    $self->_handle_related_up;
}

sub related_up : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    $self->_handle_related_up;
}

sub lock_val : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $key     = $self->class_key;
    my $value   = $self->value;
    my $autopop = ref $self->value ? $self->value : [$self->value];
    my $element = get_state_data($key => 'element');

    # Map all the data elements into a hash keyed by Element::Field ID.
    my $fields = { map  { $_->get_id => $_ } $element->get_fields };

    foreach my $id (@$autopop) {
        my $field = $fields->{$id} or next;
        if (exists $param->{"$key|lock_val_$id"}) {
            $field->lock_val;
        } else {
            $field->unlock_val;
        }
    }
}

sub save_and_up : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    if ($self->params->{$self->class_key . '|delete'}) {
        $self->_delete_element;
        return;
    }

    if (get_state_data($self->class_key, '__NO_SAVE__')) {
        # Do nothing.
        set_state_data($self->class_key, '__NO_SAVE__', undef);
    } else {
        my $element = get_state_data($self->class_key, 'element');
        my $widget  = $self->class_key;
        if ( $param->{"$widget|file"} && !$element->get_related_media_id ) {
            $self->create_related_media;
        } else {
            # Save the element we are working on.
            $element->save();
            add_msg('Element "[_1]" saved.', $element->get_name);
            $self->_pop_and_redirect;
        }
    }
}

sub save_and_stay : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    if ($self->params->{$self->class_key . '|delete'}) {
        $self->_delete_element;
        return;
    }

    if (get_state_data($self->class_key, '__NO_SAVE__')) {
        # Do nothing.
        set_state_data($self->class_key, '__NO_SAVE__', undef);
    } else {
        my $element = get_state_data($self->class_key, 'element');
        my $widget  = $self->class_key;
        if ( $param->{"$widget|file"} && !$element->get_related_media_id ) {
            $self->create_related_media;
        } else {
            # Save the element we are working on
            $element->save();
            add_msg('Element "[_1]" saved.', $element->get_name);
        }
    }
}

sub up : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    $self->_pop_and_redirect;
}

# bulk edit callbacks

sub change_default_field : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    my $def     = $self->params->{$self->class_key.'|default_field'};
    my $element = get_state_data($self->class_key, 'element');
    my $at      = $element->get_element_type();
    my $key     = 'container_prof.' . $at->get_id . '.def_field';

    # Handle whatever changes have been made with the old def field.
    $self->_handle_bulk_save(get_state_data(_tmp_prefs => $key));
    # Set the new default field.
    set_state_data('_tmp_prefs', $key, $def);
}

sub bulk_edit_this : Callback {
    my $self = shift;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};

    # Note that we are just 'flipping' the current view of this element.  That is,
    # it's the same element, same data, but different view of it.
    set_state_data($self->class_key, 'view_flip', 1);
    set_state_name($self->class_key, 'edit_bulk');

    my $element = get_state_data($self->class_key, 'element');
    my $uri  = $element->get_object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;

    $self->set_redirect("$uri/edit_bulk.html");
}

sub bulk_save : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};
    $self->_handle_bulk_save;
}

sub bulk_up : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{'_inconsistent_state_'};
    $self->_handle_bulk_up;
}

sub bulk_save_and_up : Callback {
    my ($self) = @_;
    $self->_drift_correction;
    my $param = $self->params;
    return if $param->{_inconsistent_state_};
    $self->_handle_bulk_save;
    $self->_handle_bulk_up;
}


####################
## Misc Functions ##

sub _push_element_stack {
    my ($self, $new_element) = @_;
    my $widget = $self->class_key;

    # Push the current element onto the stack.
    my $elements    = get_state_data($widget, 'elements');
    my $cur_element = get_state_data($widget, 'element');
    push @$elements, $cur_element;

    my $crumb = '';
    foreach my $t (@$elements[1..$#$elements]) {
        $crumb .= ' &quot;' . $t->get_name . '&quot;' . ' |';
    }
    $crumb .= ' &quot;' . $new_element->get_name . '&quot;';

    set_state_data($widget, 'crumb', $crumb);
    set_state_data($widget, 'elements', $elements);
    set_state_data($widget, 'element', $new_element);
}

sub _pop_element_stack {
    my ($widget) = @_;

    my $elements = get_state_data($widget, 'elements');
    my $parent_element = pop @$elements;

    my $crumb = '';
    foreach my $t (@$elements[1..$#$elements]) {
        $crumb .= ' &quot;' . $t->get_name . '&quot;' . ' |';
    }
    $crumb .= ' &quot;' . $parent_element->get_name . '&quot;';

    set_state_data($widget, 'crumb', $crumb);
    set_state_data($widget, 'element', $parent_element);
    set_state_data($widget, 'elements', $elements);
    return $parent_element;
}

sub _pop_and_redirect {
    my ($self, $flip) = @_;
    my $widget = $self->class_key;
    my $r = $self->apache_req;

    # Get the element stack and pop off the current element.
    my $element = $flip ? get_state_data($widget, 'element')
                        : _pop_element_stack($widget);

    my $object_type = $element->get_object_type;

    # If our element has parents, show the regular edit screen.
    if ($element->get_parent_id) {
        my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
        my $page = get_state_name($widget) eq 'view' ? '' : 'edit.html';

        #  Don't redirect if we're already at the right URI
        $self->set_redirect("$uri/$page") unless $r->uri eq "$uri/$page";
    }
    # If our element doesn't have parents go to the main story edit screen.
    else {
        my $uri = $object_type eq 'media' ? $MEDIA_URL : $STORY_URL;
        $self->set_redirect($uri);
    }
}

sub _delete_element {
    my $self = shift;
    my $r = $self->apache_req;
    my $widget = $self->class_key;

    my $element = get_state_data($widget, 'element');
    my $parent = _pop_element_stack($widget);
    $parent->delete_elements( [ $element ]);
    $parent->save();
    my $object_type = $parent->get_object_type;

    # if our element has parents, show the regular edit screen.
    if ($parent->get_parent_id) {
        my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
        my $page = get_state_name($widget) eq 'view' ? '' : 'edit.html';

        #  Don't redirect if we're already at the right URI
        $self->set_redirect("$uri/$page") unless $r->uri eq "$uri/$page";
    }
    # If our element doesn't have parents go to the main story edit screen.
    else {
        my $uri = $object_type eq 'media' ? $MEDIA_URL : $STORY_URL;
        $self->set_redirect($uri);
    }

    add_msg('Element "[_1]" deleted.', $element->get_name);
    return;
}


sub _update_parts {
    my ($self, $param) = @_;
    my (@curr_elements, @delete, $locate_element);

    my $widget = $self->class_key;
    my $locate_id = $self->value;
    my $element = get_state_data($widget, 'element');
    my $object_type = $element->get_object_type;

    # Don't delete unless either the 'Save...' or 'Delete' buttons were pressed
    # in the element profile or the document profile.
    my $do_delete = $param->{$widget.'|delete_cb'} ||
                    $param->{$widget.'|save_and_up_cb'} ||
                    $param->{$widget.'|save_and_stay_cb'} ||
                    $param->{$object_type .'_prof|save_cb'} ||
                    $param->{$object_type .'_prof|save_and_stay_cb'};

    # Save data to elements and put them in a usable order
    foreach my $t ($element->get_elements) {
        my $id      = $t->get_id;
        my $is_cont = $t->is_container;

        # Grab the element we're looking for
        {
            local $^W = undef;
            $locate_element = $t if $id == $locate_id and $is_cont;
        }
        if ($do_delete
            && (($is_cont && $param->{$widget . "|delete_cont$id"})
                || (!$is_cont && $param->{$widget . "|delete_data$id"}))
        ) {
            add_msg('Element "[_1]" deleted.', $t->get_name);
            push @delete, $t;
            next;
        }

        my ($order, $redir);
        if ($t->is_container) {
            $order = $param->{$widget . "|reorder_con$id"};
        } else {
            $order = $param->{$widget . "|reorder_dat$id"};
            if (! $t->is_autopopulated or exists
                $param->{$widget . "|lock_val_$id"}) {
                my $val = $param->{$widget . "|$id"};
                $val = '' unless defined $val;
                if ( $param->{$widget . "|${id}-partial"} ) {
                    # The date is only partial. Send them back to to it again.
                    add_msg('Invalid date value for "[_1]" field.', $t->get_name);
                    set_state_data($widget, '__NO_SAVE__', 1);
                } else {
                    # Truncate the value, if necessary, then set it.
                    my $max = $t->get_max_length;
                    eval {
                        if (ref $val && $t->is_multiple) {
                            if ($max) {
                                $_ = substr($_, 0, $max)
                                    for grep { length $_ > $max } @$val;
                            }
                            $t->set_values(@$val);
                        } else {
                            $val = substr($val, 0, $max)
                                if $max && length $val > $max;
                            $t->set_value($val);
                        }
                    };
                    if (my $err = $@) {
                        if (isa_bric_exception($err, 'Error')) {
                            $err->rethrow;
                        }
                        elsif (ref $err) {
                            throw_invalid $err->error;
                        }
                        else {
                            throw_invalid $err
                        }
                    }
                }
            }
        }

        $curr_elements[$order] = $t;
    }

    # Delete elements as necessary.
    $element->delete_elements(\@delete) if $do_delete && @delete;

    if (@curr_elements) {
        eval { $element->reorder_elements([ grep { defined } @curr_elements ]) };
        if ($@) {
            add_msg("Warning! State inconsistent: Please use the buttons "
                    . "provided by the application rather than the 'Back'/"
                    . "'Forward' buttons.");
            return $locate_element;
        }
    }

    set_state_data($widget, 'element', $element);
    return $locate_element;
}

sub _handle_related_up {
    my ($self) = @_;
    my $r = $self->apache_req;

    my $element = get_state_data($self->class_key, 'element');
    my $object_type = $element->get_object_type();

    # If our element has parents, show the regular edit screen.
    if ($element->get_parent_id()) {
        my $uri = $object_type eq 'media' ? $MEDIA_CONT : $CONT_URL;
        my $page = get_state_name($self->class_key) eq 'view' ? '' : 'edit.html';

        #  Don't redirect if we're already at the right URI
        $self->set_redirect("$uri/$page") unless $r->uri eq "$uri/$page";
    }
    # If our element doesn't have parents go to the main story edit screen.
    else {
        my $uri = $object_type eq 'media' ? $MEDIA_URL : $STORY_URL;
        $self->set_redirect($uri);
    }
    pop_page();
}


################################################################################
## Bulk Edit Helper Functions

sub _handle_bulk_up {
    my $self = shift;
    my $widget = $self->class_key;

    # Set the state back to edit mode.
    set_state_name($widget => 'edit');

    # If the view has been flipped, just flip it back.
    if (get_state_data($widget => 'view_flip')) {
        # Set flip back to false.
        set_state_data($widget, view_flip => 0);
        $self->_pop_and_redirect(1);
    } else {
        $self->_pop_and_redirect(0);
    }
}

sub _handle_bulk_save {
    my ($self, $def_field) = @_;
    my $params  = $self->params;
    my $widget  = $self->class_key;
    my $element = get_state_data($widget => 'element');
    $def_field  = $params->{"$widget|default_field"}
        unless defined $def_field;

    eval {
        $element->update_from_pod($params->{"$widget|text"}, $def_field);
        $element->save;
    };
    if (my $err = $@) {
        # Let the UI know that it should use the content entered by the user.
        $params->{__use_text__} = 1;
        $err->rethrow;
    }
}

###

sub _drift_correction {
    my ($self) = @_;
    my $param = $self->params;

    # Don't do anything if we've already corrected ourselves.
    return if $param->{'_drift_corrected_'};

    # Update the state name
    set_state_name($self->class_key, $param->{$self->class_key.'|state_name'});

    # Get the element ID this page thinks its displaying.
    my $element_id = $param->{$self->class_key.'|top_stack_element_id'};

    # Return if the page doesn't send us a element_id
    return unless $element_id;

    my $element  = get_state_data($self->class_key, 'element');
    # Return immediately if everything is already in sync.
    if ($element->get_id == $element_id) {
        $param->{'_drift_corrected_'} = 1;
        return;
    }

    my $stack = get_state_data($self->class_key, 'elements');
    my @tmp_stack;

    while (@$stack > 0) {
        # Get the next element on the stack.
        $element = pop @$stack;
        # Finish this loop if we find our element.
        last if $element->get_id == $element_id;
        # Push this element on our temp stack just in case we can't find our ID.
        unshift @tmp_stack, $element;
        # Undef the element since its not the one we're looking for.
        $element = undef;
    }

    # If we found the element, make it the head element and save the remaining stack.
    if ($element) {
        set_state_data($self->class_key, 'element', $element);
        set_state_data($self->class_key, 'elements', $stack);
    }
    # If we didn't find the element, abort, and restore the element stack
    else {
        add_msg("Warning! State inconsistent: Please use the buttons "
                . "provided by the application rather than the 'Back'/"
                . "'Forward' buttons");

        # Set this flag so that nothing gets changed on this request.
        $param->{'_inconsistent_state_'} = 1;

        set_state_data($self->class_key, 'elements', \@tmp_stack);
    }

    # Drift has now been corrected.
    $param->{'_drift_corrected_'} = 1;
}


1;
