package Bric::App::Callback::Profile;

use base qw(Bric::App::Callback);
__PACKAGE__->register_subclass;
use constant CLASS_KEY => 'profile';

use HTML::Mason::MethodMaker('read_write' => [qw(obj type class has_perms)]);
use strict;
use Bric::App::Event qw(log_event);
use Bric::App::Authz qw(:all);
use Bric::App::Util qw(:aref :msg :history :pkg :browser);
use Bric::App::Session qw(:user);

my $excl = {'desk' => 1, 'action' => 1, 'server' => 1, element_data => 1};

my ($get_class, $chk_grp_perms);


# each subclass of Profile inherits this constructor,
# which I want to set up the common things (obj, type, class)
# and also whether the user has permission, then each callback
# will just return unless $self->has_perms
sub new {
    my $pkg = shift;
    my $self = bless($pkg->SUPER::new(@_), $pkg);

    my $param = $self->params;

    $self->type((parse_uri($self->apache_req->uri))[2]);
    $self->class($get_class->($param, $self->type));

    # Instantiate the object.
    my $id = defined $param->{$self->type . '_id'} && $param->{$self->type . '_id'} ne ''
      ? $param->{$self->type . '_id'} : undef;
    my $obj = defined $id ? $self->class->lookup({ id => $id }) : $self->class->new;
    $self->obj($obj);

    # Check the permissions.
    unless ($excl->{$self->type}
              || chk_authz($self->obj, (defined $id ? EDIT : CREATE), 1)
              || ($self->type eq 'user' && $self->obj->get_id == get_user_id()))
    {
        # If we're in here, the user doesn't have permission to do what
        # s/he's trying to do.
        add_msg("Changes not saved: permission denied.");
        $self->set_redirect(last_page());
        $self->has_perms(0);
    } else {
        $self->has_perms(1);
    }

    return $self;
}

# Group membership is handled the same way through all callbacks,
# so this method gets inherited to all profiles.

sub manage_grps :Callback {
    my $self   = shift;
    my $obj    = shift || $self->obj;
    my $param  = $self->params;
    return unless $param->{add_grp} or $param->{rem_grp};

    my @add_grps = map { Bric::Util::Grp->lookup({ id => $_ }) }
                       @{mk_aref($param->{add_grp})};

    my @del_grps = map { Bric::Util::Grp->lookup({ id => $_ }) }
                       @{mk_aref($param->{rem_grp})};

    my $is_user = ref $obj eq 'Bric::Biz::Person::User';
    my $return = 1;

    # It could be an array of objects -- See Profile::Category.
    for my $o (ref $obj eq 'ARRAY' ? @$obj : ($obj)) {
        my $all_grp_id = $obj->INSTANCE_GROUP_ID;
        # Assemble the new member information.
        foreach my $grp (@add_grps) {
            # Check permissions.
            next unless $chk_grp_perms->($grp, $all_grp_id, $is_user);

            # Add the object to the group.
            $grp->add_members([{ obj => $o }]);
            $grp->save;
            log_event('grp_save', $grp);
        }

        foreach my $grp (@del_grps) {
            # Check permissions.
            next unless $chk_grp_perms->($grp, $all_grp_id, $is_user);

            # Deactivate the object's group membership.
            foreach my $mem ($grp->has_member({ obj => $o })) {
                $mem->deactivate;
                $mem->save;
            }

            $grp->save;
            log_event('grp_save', $grp);
        }
    }
}

$chk_grp_perms = sub {
    my ($grp, $all_grp_id, $is_user) = @_;
    # If it's a user group, disallow access unless the current user is the
    # global admin or a member of the group. If it's not a user group,
    # disallow access unless the current user has EDIT access to the members
    # of the group.
    unless ($grp->get_id != $all_grp_id
            && chk_authz($grp, EDIT, 1)
            && (($is_user
                 && (user_is_admin || $grp->has_member({ obj => get_user_object }))
                || chk_authz(0, EDIT, 1, $grp->get_id)))) {
        add_msg('Permission to manage "[_1]" group membership denied',
                $grp->get_name);
        return;
    }
    return 1;
};

###

$get_class = sub {
    my ($param, $type) = @_;

    my $key = $type;
    if ($type eq 'contrib' && ! defined $param->{'contrib_id'}) {
        $key = 'person';
    }

    my $class = get_package_name($key);
    if ($type eq 'grp' && defined $param->{'grp_type'}) {
        $class = $param->{'grp_type'};
    }

    return $class;
};


1;