package Teng::Row;
use strict;
use warnings;
use Carp ();
our $AUTOLOAD;

sub new {
    my ($class, $args) = @_;

    my $self = bless {%$args}, $class;
    $self->{select_columns} = [keys %{$self->{row_data}}];
    $self->{_get_column_cached} = {};
    $self->{_dirty_columns} = {};
    $self->{table} = $self->{skin}->schema->get_table($self->{table_name});
    return $self;
}

sub _lazy_get_data {
    my ($x, $col) = @_;

    return sub {
        my $self = shift;

        if ($self->{_untrusted_row_data}->{$col}) {
            Carp::carp("${col}'s row data is untrusted. by your update query.");
        }
        my $cache = $self->{_get_column_cached};
        my $data = $cache->{$col};
        if (! $data) { 
            $data = $cache->{$col} = $self->{table} ? $self->{table}->call_inflate($col, $self->get_column($col)) : $self->get_column($col);
        }
        return $data;
    };
}

sub handle { $_[0]->{skin} }

sub get_column {
    my ($self, $col) = @_;

    unless ( $col ) {
        Carp::croak('please specify $col for first argument');
    }

    my $row_data = $self->{row_data};
    if ( exists $row_data->{$col} ) {
        return $row_data->{$col};
    } else {
        Carp::croak("$col no selected column. SQL: " . ( $self->{sql} || 'unknown' ) );
    }
}

sub get_columns {
    my $self = shift;

    my %data;
    for my $col ( @{$self->{select_columns}} ) {
        $data{$col} = $self->get_column($col);
    }
    return \%data;
}

sub set_column {
    my ($self, $col, $val) = @_;

    if (ref($val) eq 'SCALAR') {
        $self->{_untrusted_row_data}->{$col} = 1;
    }

    $self->{row_data}->{$col} = $val;
    $self->{_get_column_cached}->{$col} = $val;
    $self->{_dirty_columns}->{$col} = 1;
}

sub set_columns {
    my ($self, $args) = @_;

    for my $col (keys %$args) {
        $self->set_column($col, $args->{$col});
    }
}

sub get_dirty_columns {
    my $self = shift;

    my %rows = map {$_ => $self->get_column($_)}
               keys %{$self->{_dirty_columns}};

    return \%rows;
}

sub update {
    my ($self, $upd, $table_name) = @_;

    if (ref($self) eq 'Teng::Row') {
        Carp::croak q{can't update from basic Teng::Row class.};
    }

    $table_name ||= $self->{table_name};
    $self->set_columns($upd);

    $self->{skin}->update($table_name, $self->get_dirty_columns, $self->_where_cond($table_name));
}

sub delete {
    my ($self, $table_name) = @_;

    if (ref($self) eq 'Teng::Row') {
        Carp::croak q{can't delete from basic Teng::Row class.};
    }

    $table_name ||= $self->{table_name};
    $self->{skin}->delete($table_name, $self->_where_cond($table_name));
}

sub refetch {
    my ($self, $table_name) = @_;
    $table_name ||= $self->{table_name};
    $self->{skin}->single($table_name, $self->_where_cond($table_name));
}

sub _where_cond {
    my ($self, $table_name) = @_;

    my $table = $self->{skin}->schema->get_table( $table_name );
    unless ($table) {
        Carp::croak("Unknown table: $table_name");
    }

    # get target table pk
    my $pk = $table->primary_keys;
    unless ($pk) {
        Carp::croak("$table_name has no primary key.");
    }

    # multi primary keys
    if ( ref $pk eq 'ARRAY' ) {
        my %pks = map { $_ => 1 } @$pk;

        unless ( ( grep { exists $pks{ $_ } } @{$self->{select_columns}} ) == @$pk ) {
            Carp::croak "can't get primary columns in your query.";
        }

        return +{ map { $_ => $self->$_() } @$pk };
    } else {
        unless (grep { $pk eq $_ } @{$self->{select_columns}}) {
            Carp::croak "can't get primary column in your query.";
        }

        return +{ $pk => $self->$pk };
    }
}

sub AUTOLOAD{
    my $self = shift;
    my($method) = ($AUTOLOAD =~ /([^:']+$)/);
    $self->_lazy_get_data($method)->($self);
}

### don't autoload this
sub DESTROY { 1 };

1;

__END__
=head1 NAME

Teng::Row - Teng's Row class

=head1 METHODS

=over

=item $row->get_column($column_name)

    my $val = $row->get_column($column_name);

get a column value from a row object.

=item $row->get_columns

    my %data = $row->get_columns;

Does C<get_column>, for all column values.

=item $row->set_columns(\%new_row_data)

    $row->set_columns({$col => $val});

set columns data.

=item $row->set_column($col => $val)

    $row->set_column($col => $val);

set column data.

=item $row->get_dirty_columns

returns those that have been changed.

=item $row->insert

insert row data. call find_or_create method.

=item $row->update([$arg, [$table_name]])

update is executed for instance record.

It works by schema in which primary key exists.

    $row->update({name => 'tokuhirom'});
    # or 
    $row->set({name => 'tokuhirom'});
    $row->update;

=item $row->delete([$table_name])

delete is executed for instance record.

It works by schema in which primary key exists.

=item my $refetched_row = $row->refetch($table_name);

$table_name is optional.

refetch record from database. get new row object.


=item $row->handle

get skin object.

    $row->handle->single('table', {id => 1});

=cut
