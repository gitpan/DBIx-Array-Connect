package DBIx::Array::Connect;
use strict;
use warnings;
use base qw{Package::New};
use Config::IniFiles qw{};
use Path::Class qw{};

our $VERSION='0.02';

=head1 NAME

DBIx::Array::Connect - Database connections from a configuration file

=head1 SYNOPSIS

  use DBIx::Array::Connect;
  my $dbx=DBIx::Array::Connect->new->connect("mydatabase");  #isa DBIx::Array

  my $dac=DBIx::Array::Connect->new(file=>"./my.ini");      #isa DBIx::Array::Connect
  my $dbx=$dac->connect("mydatabase");                      #isa DBIx::Array

=head1 DESCRIPTION

Provides an easy way to construct database objects and connect to databases while providing an easy way to centralize management of database connection strings.

This package reads database connection information from an INI formatted configuration file.

=head1 USAGE

Create an INI configuration file with the following format.  The default location for the INI file is /etc/database-connetions-config.ini on Linux-like systems and C:\Windows\database-connetions-config.ini on Windows-like systems.

  [mydatabase]
  connection=DBI:mysql:database=mydb;host=myhost.mydomain.tld
  user=myuser
  password=mypassword
  options=AutoCommit=>1, RaiseError=>1

Connect to the database.

  my $dbx=DBIx::Array::Connect->new->connect("mydatabase"); #isa DBIx::Array

Use the L<DBIx::Array> object like you normally would.

=head1 CONSTRUCTOR

=head2 new

  my $dac=DBIx::Array::Connect->new;                      #Defaults
  my $dac=DBIx::Array::Connect->new(file=>"path/my.ini"); #Override the INI location

=head1 METHODS

=head2 connect

Returns a database object for the named database.

  my $dbx=$dac->connect($name);               #isa DBIx::Array

  my %overrides=(
                 connection => $connection,
                 user       => $user,
                 password   => $password,
                 options    => {},
                 execute    => [],
                );
  my $dbx=$dac->connect($name, \%overrides);  #isa DBIx::Array

=cut

sub connect {
  my $self=shift;
  my $database=shift or die("Error: connect method requires name parameter.");
  my $override=shift;
  $override={} unless ref($override) eq "HASH";
  my $connection= $override->{"connection"} || $self->cfg->val($database, "connection")
            or die(qq{Error: connection not defined for database "$database"});
  my $user      = $override->{"user"}       || $self->cfg->val($database, "user",     "");
  my $password  = $override->{"password"}   || $self->cfg->val($database, "password", "");
  my %options=();
  if (ref($override->{"options"}) eq "HASH") {
    %options=%{$override->{"options"}};
  } else {
    my $options=$self->cfg->val($database, "options", "");
    %options=map {s/^\s*//;s/\s*$//;$_} split(/[,=>]+/, $options);
  }
  my $class=$self->class;
  eval("use $class");
  my $dbx=$class->new(name=>$database);
  $dbx->connect($connection, $user, $password, \%options);
  if ($dbx->can("execute")) {
    my @execute=();
    if (ref($override->{"execute"}) eq "ARRAY") {
      @execute=@{$override->{"execute"}};
    } else {
      @execute=grep {defined && length} $self->cfg->val($database, "execute");
    }
    $dbx->execute($_) foreach @execute;
  }
  return $dbx;
}

=head2 sections

Returns all of the "active" section names in the INI file with the given type.

  my $list=$dac->sections("db"); #[]
  my @list=$dac->sections("db"); #()
  my @list=$dac->sections;       #All "active" sections in INI file

Note: active=1 is assumed active=0 is inactive

Example:

  my @dbx=map {$dac->connect($_)} $dac->sections("db");  #connect to all active databases of type db

=cut

sub sections {
  my $self=shift;
  my $type=shift || "";
  my @list=grep {$self->cfg->val($_, "active", "1")} $self->cfg->Sections;
  @list=grep {$self->cfg->val($_, "type", "") eq $type} @list if $type;
  return wantarray ? @list : \@list;
}

=head2 class

Returns the class in to which to bless objects.  The "class" is assumed to be a base DBIx::Array object.  This package MAY work with other objects that have a connect method that pass directly to DBI->connect.  The object must have a similar execute method to support the package's execute on connect capability.

  my $class=$dac->class; #$
  $dac->class("DBIx::Array::Export"); #If you want the exports features

=cut

sub class {
  my $self=shift;
  $self->{"class"}=shift if @_;
  $self->{"class"}="DBIx::Array" unless defined $self->{"class"};
  return $self->{"class"};
}

=head2 file

Sets or returns the profile INI file name

  my $file=$dac->file;
  my $file=$dac->file("./my.ini");

Set on construction

  my $dac=DBIx::Array::Connect->new(file=>"./my.ini");

=cut

sub file {
  my $self=shift;
  if (@_) {
    $self->{'file'}=shift;
    die(sprintf(qq{Error: Cannot read file "%s".}, $self->{'file'})) unless -r $self->{'file'};
  }
  unless (defined $self->{'file'}) {
    if (ref($self->path) eq "ARRAY") {
      foreach my $path (@{$self->path}) {
        $self->{"file"}=Path::Class::file($path, $self->basename);
        last if -r $self->{"file"};
      }
    } else {
      die(sprintf(qq{Error: path method returned a "%s"; expecting an array reference.}, ref($self->{"file"})))
        unless $self->path eq "ARRAY";
    }
  }
  #We may not have a vaild file here?  We'll let Config::IniFiles catch the error.
  return $self->{'file'};
}

=head2 path

Sets and returns a list of search paths for the INI file.

  my $path=$dac->path;            # []
  my $path=$dac->path(".", ".."); # []

Default: ["/etc"] on Linux-like systems
Default: ['C:\Windows'] on Windows like systems

Overloading path name is a good way to migrate from one location to another over time.

  package My::Connect;
  use base qw{DBIx::Array::Connect};
  use Path::Class qw{};
  sub path {[".", "..", "/etc", "/home"]};

Put INI file in the same folder as tnsnames.ora file.

  package My::Connect::Oracle;
  use base qw{DBIx::Array::Connect};
  use Path::Class qw{};
  sub path {[Path::Class::dir($ENV{"ORACLE_HOME"}, "network", "admin")]};

=cut

sub path {
  my $self=shift;
  $self->{"path"}=[@_] if @_;
  unless (ref($self->{"path"}) eq "ARRAY") {
    my @path=();
    if ($^O eq "MSWin32") {
      eval("use Win32");
      push @path, eval("Win32::GetFolderPath(Win32::CSIDL_WINDOWS)");
    } else {
      eval("use Sys::Path");
      push @path, eval("Sys::Path->sysconfdir");
    }
    $self->{"path"}=\@path;
  }
  return $self->{"path"};
}

=head2 basename

Returns the INI basename.

You may want to overload the basename property if you inherit this package.

  package My::Connect;
  use base qw{DBIx::Array::Connect};
  sub basename {"whatever.ini"};

Default: database-connections-config.ini

=cut

sub basename {
  my $self=shift;
  $self->{"basename"}=shift if @_;
  $self->{"basename"}="database-connections-config.ini"
    unless $self->{"basename"};
  return $self->{"basename"};
}

=head2 cfg

Returns the L<Config::IniFiles> object so that you can read additional information from the INI file.

  my $cfg=$dac->cfg; #isa Config::IniFiles

Example

  my $connection_string=$dac->cfg->val($database, "connection");

=cut

sub cfg {
  my $self=shift;
  my $file=$self->file; #support for objects that can stringify paths.
  $self->{'cfg'}=Config::IniFiles->new(-file=>"$file")
    unless ref($self->{'cfg'}) eq "Config::IniFiles";
  return $self->{'cfg'};
}

=head1 INI File Format

=head2 Section

The INI section name is value that needs to be passed in the connect method.

  [section]

  my $dbx=DBIx::Array::Connect->new->connect("section");

=head2 connection

The string passed to DBI to connect to the database.

Examples:

  connection=DBI:CSV:f_dir=.
  connection=DBI:mysql:database=mydb;host=myhost.mydomain.tld
  connection=DBI:Sybase:server=mssqlserver.mydomain.tld;datasbase=mydb
  connection=DBI:Oracle:DBTNSNAME

=head2 user

The string passed to DBI as the user.  Default is "" for user-less drivers.

=head2 password

The string passed to DBI as the password.  Default is "" for password-less drivers.

=head2 options

Parsed and passed as a hash reference to DBI->connect.

  options=AutoCommit=>1, RaiseError=>1, ReadOnly=>1

=head2 execute

Connection settings that you want to execute every time you connect

  execute=ALTER SESSION SET NLS_DATE_FORMAT = 'MM/DD/YYYY HH24:MI:SS'
  execute=INSERT INTO mylog (mycol) VALUES ('Me')

=head2 type

Allows grouping database connections in groups.

  type=group

=head2 active

This option is used by the sections method to filter out databases that may be temporarily down.

  active=1
  active=0

Default: 1

=head1 LIMITATIONS

Once the file method has cached a filename, basename and path are ignored. Once the Config::IniFiles is constructed the file method is ignored.  If you want to use two different INI files, you should construct two different objects.

The file, path and basename methods are common exports from other packages.  Be wary!

=head1 BUGS

Send email to author and log on RT.

=head1 SUPPORT

DavisNetworks.com supports all Perl applications including this package.

=head1 AUTHOR

  Michael R. Davis
  CPAN ID: MRDVT
  Satellite Tracking of People, LLC
  mdavis@stopllc.com
  http://www.stopllc.com/

=head1 COPYRIGHT

This program is free software licensed under the...

  The General Public License (GPL)
  Version 2, June 1991

The full text of the license can be found in the LICENSE file included with this module.

=head1 SEE ALSO

L<DBIx::Array>, L<Config::IniFiles>

=cut

1;
