
package CouchDB::Client::DB;

use strict;
use warnings;

our $VERSION = $CouchDB::Client::VERSION;

use Carp        qw(confess);
use URI::Escape qw(uri_escape_utf8);
use CouchDB::Client::Doc;
use CouchDB::Client::DesignDoc;

sub new {
    my $class = shift;
    my %opt = @_ == 1 ? %{$_[0]} : @_;

    $opt{name}   || confess "CouchDB database requires a name.";
    $opt{client} || confess "CouchDB database requires a client.";
    $opt{name} .= '/' unless $opt{name} =~ m{/$};
    
    return bless \%opt, $class;
}

sub validName {
    shift;
    my $name = shift;
    return $name =~ m{^[a-z0-9_\$\(\)\+/-]+/$};
}

sub uriName {
    my $self = shift;
    my $sn = $self->{name};
    $sn =~ s{/(.)}{%2F$1}g;
    return "$sn";
}

sub dbInfo {
    my $self = shift;
    my $res = $self->{client}->req('GET', $self->uriName);
    return $res->{json} if $res->{success};
    CouchDB::Client::Ex::ConnectError->throw( message => $res->{msg});
}

sub create {
    my $self = shift;
    my $res = $self->{client}->req('PUT', $self->uriName);
    return $self if $res->{success} and $res->{json}->{ok};
    CouchDB::Client::Ex::DBExists->throw( message => $res->{msg}, name => $self->{name}) if $res->{status} == 409;
    CouchDB::Client::Ex::ConnectError->throw( message => $res->{msg});
}

sub delete {
    my $self = shift;
    my $res = $self->{client}->req('DELETE', $self->uriName);
    return 1 if $res->{success} and $res->{json}->{ok};
    CouchDB::Client::Ex::NotFound->throw( message => $res->{msg}, name => $self->{name}) if $res->{status} == 404;
    CouchDB::Client::Ex::ConnectError->throw( message => $res->{msg});
}

sub newDoc {
    my $self = shift;
    my $id = shift;
    my $rev = shift;
    my $data = shift;
    my $att = shift;
    return CouchDB::Client::Doc->new(id => $id, rev => $rev, data => $data, attachments => $att, db => $self);
}

sub listDocIdRevs {
    my $self = shift;
    my %args = @_;
    my $qs = %args ? $self->argsToQuery(%args) : '';
    my $res = $self->{client}->req('GET', $self->uriName . '_all_docs' . $qs);
    CouchDB::Client::Ex::ConnectError->throw( message => $res->{msg} ) unless $res->{success};
    return [map { { id => $_->{id}, rev => $_->{value}->{_rev} } } @{$res->{json}->{rows}}];
}

sub listDocs {
    my $self = shift;
    my %args = @_;
    return [ map { $self->newDoc($_->{id}, $_->{rev}) } @{$self->listDocIdRevs(%args)} ];
}

sub docExists {
    my $self = shift;
    my $id = shift;
    my $rev = shift;
    if ($rev) {
        return (grep { $_->{id} eq $id and $_->{rev} eq $rev } @{$self->listDocIdRevs}) ? 1 : 0;
    }
    else {
        return (grep { $_->{id} eq $id } @{$self->listDocIdRevs}) ? 1 : 0;
    }
}

sub newDesignDoc {
    my $self = shift;
    my $id = shift;
    my $rev = shift;
    my $data = shift;
    return CouchDB::Client::DesignDoc->new(id => $id, rev => $rev, data => $data, db => $self);
}

sub listDesignDocIdRevs {
    my $self = shift;
    my %args = @_;
    return [grep { $_->{id} =~ m{^_design/} } @{$self->listDocIdRevs(%args)}];
}

sub listDesignDocs {
    my $self = shift;
    my %args = @_;
    return [ map { $self->newDesignDoc($_->{id}, $_->{rev}) } @{$self->listDesignDocIdRevs(%args)} ];
}

sub designDocExists {
    my $self = shift;
    my $id = shift;
    my $rev = shift;
    $id = "_design/$id" unless $id =~ m{^_design/};
    if ($rev) {
        return (grep { $_->{id} eq $id and $_->{rev} eq $rev } @{$self->listDesignDocIdRevs}) ? 1 : 0;
    }
    else {
        return (grep { $_->{id} eq $id } @{$self->listDesignDocIdRevs}) ? 1 : 0;
    }
}

# from docs
# key=keyvalue 
# startkey=keyvalue 
# startkey_docid=docid 
# endkey=keyvalue 
# count=max rows to return 
# update=false 
# descending=true 
# skip=rows to skip 
sub fixViewArgs {
    my $self = shift;
    my %args = @_;
    
    for my $k (keys %args) {
        if ($k eq 'key' or $k eq 'startkey' or $k eq 'endkey') {
            if (ref($args{$k}) eq 'ARRAY' or ref($args{$k}) eq 'HASH') {
                $args{$k} = $self->server->json->encode($args{$k});
            }
            else {
                $args{$k} = '"' . $args{$k} . '"';
            }
        }
        elsif ($k eq 'descending') {
            if ($args{$k}) {
                $args{$k} = 'true';
            }
            else {
                delete $args{$k};
            }
        }
        elsif ($k eq 'update') {
            if ($args{$k}) {
                delete $args{$k};
            }
            else {
                $args{$k} = 'false';
            }
        }
    }
    return %args;
}

sub argsToQuery {
    my $self = shift;
    my %args = @_;
    %args = $self->fixViewArgs(%args);
    return  '?' .
            join '&',
            map { uri_escape_utf8($_) . '=' . uri_escape_utf8($args{$_}) }
            keys %args;
}

1;

=pod

=head1 NAME

CouchDB::Client::DB - CouchDB::Client database

=head1 SYNOPSIS

    use CouchDB::Client;
    ...

=head1 DESCRIPTION

This module represents databases in the CouchDB database.

We don't currently handle the various options available on listing all documents.

=head1 METHODS

=over 8

=item new

Constructor. Takes a hash or hashref of options, both of which are required: 
C<name> being the name of the DB (do not escape it, that is done internally,
however the name isn't validated, you can use C<validName> for that) and C<client>
being a reference to the parent C<Couch::Client>. It is not expected that
you would use this constructor directly, but rather that would would go through
C<<< Couch::Client->newDB >>>.


=item validName $NAME

Returns true if the name is a valid CouchDB database name, false otherwise.

=item dbInfo

Returns metadata that CouchDB maintains about its databases as a Perl structure.
It will throw a C<CouchDB::Client::Ex::ConnectError> if it can't connect.
Typically it will look like:

    {
        db_name         => "dj", 
        doc_count       => 5, 
        doc_del_count   => 0, 
        update_seq      => 13, 
        compact_running => 0, 
        disk_size       => 16845,
    }

=item create

Performs the actual creation of a database. Returns the object itself upon success.
Throws a C<CouchDB::Client::Ex::DBExists> if it already exists, or a
C<CouchDB::Client::Ex::ConnectError> for other problems.

=item delete

Deletes the database. Returns true on success. Throws a C<CouchDB::Client::Ex::NotFound> if
the DB can't be found, and C<CouchDB::Client::Ex::ConnectError> for other problems.

=item newDoc $ID?, $REV?, $DATA?, $ATTACHMENTS?

Returns a new C<CouchDB::Client::Doc> object, optionally with the given ID, revision, data,
and attachments. Note that this does not create the actual document, simply the object. For
constraints on these fields please look at C<<<CouchDB::Client::Doc->new>>>

=item listDocIdRevs %ARGS?

Returns an arrayref containing the ID and revision of all documents in this DB as hashrefs
with C<id> and C<rev> keys. Throws a C<CouchDB::Client::Ex::ConnectError> if there's a
problem. Takes an optional hash of arguments matching those understood by CouchDB queries.

=item listDocs %ARGS?

The same as above, but returns an arrayref of C<CouchDB::Client::Doc> objects.
Takes an optional hash of arguments matching those understood by CouchDB queries.

=item docExists $ID, $REV?

Takes an ID and an optional revision and returns true if there is a document with that ID
in this DB, false otherwise. If the revision is provided, note that this will match only if
there is a document with the given ID B<and> its latest revision is the same as the given
one.

=item newDesignDoc $ID?, $REV?, $DATA?

Same as above, but instantiates design documents.

=item listDesignDocIdRevs %ARGS?

Same as above, but only matches design documents.

=item listDesignDocs %ARGS?

Same as above, but only matches design documents.

=item designDocExists $ID, $REV?

Same as above, but only matches design documents.

=item uriName

Returns the name of the database escaped.

=item fixViewArgs %ARGS

Takes a hash of view parameters expressed in a Perlish fashion (e.g. 1 for true or an arrayref
for multi-valued keys) and returns a hash with the same options turned into what CouchDB 
understands.

=item argsToQuery %ARGS

Takes a hash of view parameters, runs them through C<fixViewArgs>, and returns a query
string (complete with leading '?') to pass on to CouchDB.

=back

=head1 AUTHOR

Robin Berjon, <robin @t berjon d.t com>

=head1 BUGS 

Please report any bugs or feature requests to bug-couchdb-client at rt.cpan.org, or through the
web interface at http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CouchDb-Client.

=head1 COPYRIGHT & LICENSE 

Copyright 2008 Robin Berjon, all rights reserved.

This library is free software; you can redistribute it and/or modify it under the same terms as 
Perl itself, either Perl version 5.8.8 or, at your option, any later version of Perl 5 you may 
have available.

=cut
