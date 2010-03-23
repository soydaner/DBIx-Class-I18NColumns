package DBIx::Class::I18NColumns;

use warnings;
use strict;
use base qw/DBIx::Class/;
use Scalar::Util qw(blessed);
use Class::C3::Componentised;

our $VERSION = '0.01';

__PACKAGE__->mk_classdata('_i18n_columns');
__PACKAGE__->mk_group_accessors( 'simple' => qw/ language _i18n_column_data / );

=head1 NAME

DBIx::Class::I18NColumns - Internationalization for DBIx::Class Result class

=head1 VERSION

Version 0.01

=cut

=head1 SYNOPSIS


    package MySchema::Result::Song;

    use strict;
    use warnings;
    use parent 'DBIx::Class';

    __PACKAGE__->load_components( qw/ I18NColumns ForceUTF8 Core / );

    __PACKAGE__->table( 'song' );
    __PACKAGE__->add_columns(
        'id',
        { data_type => 'INT', default_value => 0, is_nullable => 0 },
        'author',
        { data_type => 'VARCHAR', default_value => "", is_nullable => 0, size => 255 },
    );
    __PACKAGE__->add_i18n_columns(
        'title',
        { data_type => 'VARCHAR', default_value => "", is_nullable => 0, size => 255 },
        'lyrics',
        { data_type => 'TEXT', default_value => "", is_nullable => 0 },
    );

    __PACKAGE__->set_primary_key( 'id' );
    
    1;

    # then, you have an auto generated resultset where title and lyrics are stored
    # in different languages:

    my $song = $myschema->resultset( 'Song' )->create({
        author   => 'Flopa',
        title    => 'Germinar',
        lyrics   => 'La vida se toma como el vino pura, y ...',
        language => 'es',
    });

    print $song->title; # prints 'Germinar'

    $song->language('en');
    $song->title('To germinate');      # set title in english
    $song->lyrics('traslated lyrics'); # set lyrics in english
    $song->update;                     # store title and lyrics

    print $song->title;         # prints 'To Germinate'
    print $song->title(['es']); # prints 'Germinar'
    $song->language('es');
    print $song->title;         # prints 'Germinar'

=cut

=head2 add_i18n_columns
    
    Create internationalizable columns. The columns are created in the same 
    way you do with in L<add_columns|DBIx::Class::ResultSource/add_columns>.

    Only text and varchar columns can be user. If you don't specify the data_type,
    varchar will be used by default.

=cut
sub add_i18n_columns {
    my $self    = shift;
    my @columns = @_;

    $self->_i18n_columns( {} ) unless defined $self->_i18n_columns();
    $self->resultset_class( 'DBIx::Class::ResultSet::I18NColumns' );
    $self->_create_i18n_result_source if $self->auto_i18n_rs;

    # Add columns & accessors
    while ( my $column = shift @columns ) {
        my $column_info = ref $columns[0] ? shift(@columns) : {};
        $column_info->{data_type} = lc( $column_info->{data_type} || 'varchar' ); 

        # Check column
        $self->throw_exception( "Cannot override existing column '$column' with this i18n one" )
            if ( $self->has_column($column) || exists $self->_i18n_columns->{$column} );

        $self->_i18n_columns->{$column} = $column_info;

        my $accessor = $column_info->{accessor} || $column;

        # Add accessor
        no strict 'refs';
        *{ $self . '::' . $accessor } = sub {
            my $self = shift;
            $self->_i18n_method( $column => @_ );
        };
    }
}

sub _create_i18n_result_source {
    my $self = shift;

    if ( my $tablename = $self->table ) {
        my $class = $self->result_class . 'I18N';
        Class::C3::Componentised->inject_base( $class, 'DBIx::Class' );

        $class->load_components(qw/ ForceUTF8 Core /);
        $class->table( $tablename . '_i18n' );
        my $fk_name = 'id_' . $tablename; 
        $class->add_columns(
            $fk_name,
            { data_type => 'INT', default_value => 0, is_nullable => 0 },
            'language',
            {
                data_type     => 'VARCHAR',
                default_value => '',
                is_nullable   => 0,
                size          => 2
            },
            'attr',
            { data_type => 'VARCHAR', is_nullable => 0, size => 32 },
            'varchar',
            { data_type => 'VARCHAR', is_nullable => 1, size => 255 },
            'text',
            { data_type => 'TEXT', is_nullable => 1 },
        );

        $class->set_primary_key( $fk_name, "language", "attr" );
        $self->schema_class->register_class( $self->_i18n_class_moniker => $class );
    }
    else {
        $self->throw_exception(
            "Cannot create table for i18n strings without a table set on "
              . $self->result_class );
    }
}

=head2 schema_class
=cut
sub schema_class {
    my $self = shift;

    if ( blessed($self) ) {
        return blessed( $self->result_source->schema );
    }

    # this is a horrible and fragile hack to find the schema class :(
    my $schema_class = $self;
    $schema_class =~ s/::Result.+$//;
    return $schema_class;
}

sub _i18n_method {
    my ( $self, $column ) = ( shift, shift );
    
    my $old_language = $self->language;
    $self->language(pop->[0]) if scalar @_ && ref $_[-1]; 

    $self->throw_exception( "Cannot get or set an i18n column with no language defined" )
        unless $self->language;

    my $ret;
    if ( my $value = shift ) {
        $ret = $self->set_column( $column => $value );
    }
    else {
        $ret = $self->get_column( $column );
    }

    $self->language($old_language);

    return $ret; 
}

=head2 i18n_resultset
=cut
sub i18n_resultset {
    my $self = shift;


    return $self->result_source->schema->resultset( $self->_i18n_class_moniker );
}

sub _i18n_class_moniker {
    my $self = shift;
    my $i18n_rs_class = ( blessed( $self ) || $self ) . 'I18N';
    my ($i18n_rs_name) = $i18n_rs_class =~ /([^:]+)$/;
}

=head2 auto_i18n_rs

By default, this component will autocreate the result class that will be 
used to store internationalized values.
You should overwrite this method to stop this component to do this and
then you must create is manually.

In your result class that use this component:

    sub auto_i18n_rs { 0 }

=cut

sub auto_i18n_rs { 1 }

=head2 language_column
    
The name for the language column to be used and autocreated.
Defaults on 'language'.

=cut

sub language_column { 'language' }

=head2 foreign_column

The name for the column to store the PK of the internationalized
result class.
Defaults on id_[table name of result source]

=cut
sub foreign_column { 'id_' . shift->result_source->name }

=head2 has_any_column

Returns true if the source has a i18n or regular column of this name, 
false otherwise.

=cut

sub has_any_column {
    my ( $self, $column ) = ( shift, shift );
    return ( $self->has_i18n_column($column) || $self->has_column($column) )
        ? 1
        : 0;
}

=head2 has_i18n_column

Returns true if the source has a i18n column of this name, false otherwise.

=cut

sub has_i18n_column {
    my ( $self, $column ) = ( shift, shift );
    return ( exists $self->_i18n_columns->{$column} ) ? 1 : 0;
}

=head2 set_column

Overloaded L<DBIx::Class::Row/set_column> to manage i18n columns cleanly. 

=cut
sub set_column {
    my ( $self, $column, $value ) = @_;

    if ( $self->has_i18n_column($column) ) {
        #TODO: do I need to make it dirty?
        return $self->store_column( $column => $value );
    }

    return $self->next::method( $column, $value );
}

=head2 store_column

Overloaded L<DBIx::Class::Row/store_column> to manage i18n columns cleanly. 

=cut
sub store_column {
    my ( $self, $column, $value ) = @_;

    $self->_i18n_column_data({}) unless $self->_i18n_column_data;
    $self->_i18n_column_data->{$column} = {} unless exists $self->_i18n_column_data->{$column};

    if ( $self->has_i18n_column($column) ) {
        my $type = $self->_i18n_columns->{$column}{data_type};
        if ( exists $self->_i18n_column_data->{$column}{ $self->language} ) {
            return $self->_i18n_column_data->{$column}{ $self->language }
                ->$type($value);
        }
        else {
            return $self->_i18n_column_data->{$column}{ $self->language }
                = $self->i18n_resultset->new({   
                    $type                  => $value,
                    $self->language_column => $self->language,
                    $self->foreign_column  => $self->id,
                    attr                   => $column,
                });
        }
    }

    return $self->next::method( $column, $value );
}

=head2 get_column

Overloaded L<DBIx::Class::Row/get_column> to manage i18n columns cleanly. 

=cut
sub get_column {
    my ( $self, $column ) = ( shift, shift );
    my $lang = $self->language;

    $self->_i18n_column_data({}) unless $self->_i18n_column_data;
    $self->_i18n_column_data->{$column} = {} unless exists $self->_i18n_column_data->{$column};

    if ( $self->has_i18n_column($column) ) {
        unless ( exists $self->_i18n_column_data->{$column}{$lang} ) {
            $self->_i18n_column_data->{$column}{$lang} = 
                $self->i18n_resultset->find_or_new({   
                    attr                   => $column,
                    $self->language_column => $self->language,
                    $self->foreign_column  => $self->id,
            });
        }

        my $type = $self->_i18n_columns->{$column}{data_type};
        return $self->_i18n_column_data->{$column}{$lang}->$type;
    }

    return $self->next::method( $column, @_ );
}

=head2 update

Overloaded L<DBIx::Class::Row/update> to manage i18n columns cleanly. 

=cut
sub update {
    my $self = shift;

    $self->next::method( @_ );

    if ( $self->_i18n_column_data ) {
        for my $column ( keys %{$self->_i18n_column_data} ) {
            for my $lang ( keys %{$self->_i18n_column_data->{$column}} ) {
                my $i18n_row = $self->_i18n_column_data->{$column}{$lang};
                $i18n_row->in_storage ? $i18n_row->update : $i18n_row->insert ;
            }
        }
    }

    return $self;
}

#TODO: delete
#TODO: get_columns
#TODO: get_dirty_columns

=head1 AUTHOR

Diego Kuperman, C<< <diego at freekeylabs.com > >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dbix-class-i18ncolumns at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBIx-Class-I18NColumns>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DBIx::Class::I18NColumns


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBIx-Class-I18NColumns>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DBIx-Class-I18NColumns>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DBIx-Class-I18NColumns>

=item * Search CPAN

L<http://search.cpan.org/dist/DBIx-Class-I18NColumns/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2010 Diego Kuperman.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of DBIx::Class::I18NColumns
