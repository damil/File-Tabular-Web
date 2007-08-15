use strict;
use warnings;
no warnings 'uninitialized';
use File::Basename;
use File::Tabular;
use Getopt::Long;
use Template;
use List::MoreUtils qw/uniq any all/;

my %vars = ();

my $field_sep;
my @menus;
my $override;

GetOptions("menu=s"     => \@menus,
           "fieldSep=s" => \$field_sep,
           "override!"  => \$override,
          );

my $file_name = $ARGV[0] or die "usage : $0 [options] <dataFile>";

@vars{qw/base dir suffix/} = fileparse($file_name, qr/\.[^.]*$/);

chdir $vars{dir} or die $!;

my $tab_file = File::Tabular->new("$vars{base}$vars{suffix}", 
                                  {fieldSep => $field_sep});

my @headers = $tab_file->headers;



if (@menus) {
  my %menu_values;

  # check that menus correspond to headers in datafile
  foreach my $menu (@menus) {
    any {$_ eq $menu } @headers or die "unknown menu field : $menu";
  }

  while (my $row = $tab_file->fetchrow) {
    foreach my $menu (@menus) {
      my $val = $row->{$menu};
      $menu_values{$menu}{$val} = 1;
    }
  }

  foreach my $menu (@menus) {
    $vars{menus}{$menu} = [sort keys %{$menu_values{$menu}}];
  }
}


$vars{headers}    = \@headers;
$vars{key_header} = $headers[0];
$vars{fieldSep}   = $field_sep;


# split DATA into template files (keys are filenames, values are tmpl contents)
local $/ = undef;
my (undef, %templates) = split /^__(.+?)__+\r?\n/m, <DATA>;



# create files from templates

# We will generate templates from templates, so there must be directives
# for first pass (template generation) and for second pass (runtime
# page generation). We use "{% .. %}" for first pass and default
# "[% .. %]" for second pass.
my %tmpl_config = (START_TAG => '{%', 
                   END_TAG   => '%}',
                  );

my $tmpl = Template->new(\%tmpl_config);
while (my ($name, $content) = each %templates) {
  my $output = sprintf $name, $vars{base};
  $override or not -e $output or die "$output exists, will not clobber";
  $tmpl->process(\$content, \%vars, $output) or die $tmpl->error();
}


#----------------------------------------------------------------------
# END OF MAIN PROGRAM. DATA SECTION BELOW CONTAINS THE TEMPLATES
#----------------------------------------------------------------------


__DATA__

__%s.ftw___________________________________________________________________
# GLOBAL SECTION
{%- IF fieldSep %}
fieldSep = {% fieldSep %}
{% END # IF fieldSep -%}

avoidMatchKey true         # searches will not match on first field (key)
preMatch <span class=HL>   # string to insert for highlight
postMatch </span>          # end string to insert for highlight

[application]
mtime = %d.%m.%Y %H:%M:%S


[fixed]  # parameters in this section cannot be overridden by CGI parameters

max = 99999                # max records retrieved

[default] # parameters in this section can be overridden by CGI parameters

count = 50                 # how many records in a result slice

[fields]

autoNum {% key_header %}   # automatic numbering for new records


__%s_wrapper.tt____________________________________________________________
<html>
<head>
  <title>{% base %} -- File::Tabular::Web application</title>
  <style>
    .HL {background: magenta} /* highlighting search results */
  </style>
</head>
<body>
<span style="float:right;font-size:smaller">
  A File::Tabular::Web application
</span>
<h1>{% base %}</h1>

<form method="POST">
<fieldset>
  <span style="float:right">
  <a href="?H">Home</a> <br>
  <a href="?S=*">All</a>
  </span>

  {% FOREACH menu IN menus %}
    <select name="S">
      <option value="">--{% menu.key %}--</option>
     {% FOREACH val IN menu.value -%}
       <option value="+{% menu.key %}={% val %}">{% val %}</option>
     {% END # FOREACH val IN menu.value %}
    </select>
  {% END # FOREACH menu IN menus -%}
  <input name="S" size="30">
  <input type="submit" value="Search">
</fieldset>
</form>

<div style="font-size:70%;width:100%;text-align:right">
Last modified: [% self.mtime %]
</div>

[% content %]
</body>
</html>
__%s_home.tt_______________________________________________________________
[% WRAPPER {% base %}_wrapper.tt %]
<h2>Welcome</h2>

This is a web application around a single tabular file.
Type any words in the search box above. You may use boolean
combinations, '+' or '-' prefixes, sequences of words within
double quotes. You may also restrict a search word to a given 
data field, using a ":" prefix ; available fields are :
 <blockquote>
  {%- FOREACH header IN headers -%}
    {%- header -%}
    {%- " | " UNLESS loop.last -%}
  {%- END # FOREACH -%}
 </blockquote>
[% END # WRAPPER -%]

__%s_short.tt______________________________________________________________
[% WRAPPER {% base %}_wrapper.tt %]

[%- BLOCK links_prev_next -%]
  [% IF found.prev_link %]
    <a href="[% found.prev_link %]">[Previous &lt;&lt;]</a>
  [% END; # IF %]
  Displayed : <b>[% found.start %]</b> to <b>[% found.end %]</b> 
                                       from <b>[% found.count %]</b>
  [% IF found.next_link %]
    &nbsp;<a href="[% found.next_link %]">[&gt;&gt; Next]</a>
  [% END; # IF %]
[%- END # BLOCK -%]

<b>Your request </b> : [ [%- self.getCGI('S') -%] ] <br>
<b>[% found.count %]</b> records found              <br>

[% PROCESS links_prev_next %]

<table border>
[% FOREACH r IN found.records; %]
  <tr>
    <td>
    [%# dummy display; modify to choose whatever to display here %]
    {% FOREACH header IN headers; %}
      {%- IF loop.first -%}
       <a href="?L=[% r.{% header %} %]">[% r.{% header %} %]</a>
      {%- ELSE  -%}
       [%- r.{% header %} -%] 
      {%- END # IF  -%}
      {%- " | " UNLESS loop.last; -%}
    {% END # FOREACH header %}
    </td>
  </tr>
[% END # FOREACH r IN found.records; %]
</table>

[% PROCESS links_prev_next %]

[% END # WRAPPER -%]

__%s_long.tt_______________________________________________________________
[% WRAPPER {% base %}_wrapper.tt %]
[% r = found.records.0; %]

[% IF self.can_do("modif", r); %]
  <a href="?M=[% r.{% key_header %} %]" style="float:right">Modify</a>
[% END # IF; -%]

<h2>Long display of record [% r.{% key_header %} %]</h2>

<table border>
{% FOREACH header IN headers; %}
<tr>
  <td align="right">{% header %}</td>
  <td>[% r.{% header %} %]</td>
</tr>
{% END # FOREACH header %}
</table>


[% END # WRAPPER -%]

__%s_modif.tt______________________________________________________________
[%- WRAPPER {% base %}_wrapper.tt -%]
[% r = found.records.0;
   key = r.{% key_header %} %]

<form method="POST">
<input type="hidden" name="M" value="[% key %]">

<h2>Modify record [% key %]</h2>

<table border>
{% FOREACH header IN headers; 
   NEXT IF header==key_header; # skip (not allowed to edit key) 
%}
<tr>
  <td align="right">{% header %}</td>
  <td><input name="{% header %}" value="[% r.{% header %} %]" size="40"></td>
</tr>
{% END # FOREACH header %}
</table>
<input type="submit">
<input type="reset">
[% IF self.can_do("delete", r); %]
<input type=button value="Destroy" 
       onclick="if (confirm('Really?')) {location.href='?D=[% key %]';}">
[% END # IF %]

</form>

[% END # WRAPPER -%]

__%s_msg.tt________________________________________________________________
[% WRAPPER {% base %}_wrapper.tt %]

<h2>Message</h2>

<EM>[% self.msg %]</EM>

[% END # WRAPPER -%]

