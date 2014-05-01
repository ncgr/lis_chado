#! /usr/bin/env perl
=head1 NAME

gmod_bulk_load_bp_v2_pass2.pl

=head1 DESCRIPTION

 Usage:
If using GMOD database profile:

	 perl gmod_bulk_load_bp_v2_pass2.pl -g -H [dbhost] -D [dbname]  [-vt] -i file

If not using GMOD database profile: 

	perl gmod_bulk_load_bp_v2_pass2.pl -H [dbhost] -D [dbname] -d [database driver eg. 'Pg'] -u [user name] -p [password] [-vt] -i [input_file] 

	NOTE: Additionally, you can use '-t' option if you want to run the script without inserting any data into chado for trial purpose, rolling back.  

     	
This script is intended to load metadata from NCBI database 'BioProject' and their related sample(s) and Publication information from 'BioSample'  and 'PubMed' databases respectively into Chada database schema. Please note currently this script also calls another script called as 'gmod_bulk_load_pubmed_adf.pl' in order to load Publications related to each BioProject if present. 


parameters

=over 6

=item -H

hostname for database 

=item -D

database name 

=item -i 

input file [required]

=item -v

verbose output
 
=item -t

trial mode. Do not perform any store operations at all.

=item -g

GMOD database profile name (can provide host and DB name) Default: 'default'

=back

=head2 If not using a GMOD database profile (option -g) then you must provide the following parameters

=over 3

=item -u

user name 

=item -d 

database driver name (i.e. 'Pg' for postgres)

=item -p 

password for youe user to connect to the database


=back

The script stores NCBI-bioproject entries in the database.
Existing ones are ignored. 
Input file should contain a list bioproject UIDs (example: 238493). Then a new BioProject object (Bio::Chado::Schema::Project::Project) with accession= PRJNA/PRJDB/PRJEB is created,
the publication specs are fetched from Entrez (using eUtils) which sets the different fields in the Publication object. When the publication is stored, a new dbxref is stored first (see Chado General module)   

=head2 This script works with Chado schema and access and/or load data into following tables:

=over 5

=item project

=item projectprop

=item project_contact

=item project_pub

=item pub

=item organism

=item biomaterial 

=item biomaterialprop

=item biomaterial_dbxref

=item dbxref

=item contact

=item stock

=item cv

=item cvterm

=item project_biomaterial

=back


=head1 AUTHOR

Pooja Umale <peu@ncgr.org> or <pooja.umale@gmail.com>

=head1 VERSION AND DATE

Version 1, April 2014

This script is based on a model script name "gmod_bulk_load_pubmed.pl" witten by 

Naama Menda <nm249@cornell.edu>

=head1 VERSION AND DATE

Version 1.1, April 2010.

=cut



use strict;
use warnings;

use Bio::GMOD::Config;
use Bio::GMOD::DB::Config;
use Bio::Chado::Schema;
use XML::Twig;
use XML::XPath;
use XML::XPath::XMLParser;
use LWP::Simple qw/ get /;

use Getopt::Std;

our ($opt_H, $opt_D, $opt_v, $opt_t, $opt_i,  $opt_g, $opt_p, $opt_d, $opt_u);

getopts('H:D:i:p:g:p:d:u:tv');
my @getdbx_ids;
my @ele_a;
my @ele_b;
my @cvta;
my @cvtb;
my $project;
my $dbxref;
my $dbxref_s;
my $organism_s;
my $biomaterial_s;
my $desc_s;
my $project_id;
my $contact;
my $contact_s;
my $organism;
my $biomaterial;
my $project_cvterm;
my $sample_cvterm;
my $title_of_umbrella;
my @publ_ids = ();
my $aa;
my $a;
my $b;
my $c;
my $stk_id;
my $stock;
my $pt1;
my $pt2;
my $pubID;
my $cvt2;
my $cvt_a;
my $cvt_b;
my $element_a;
my $method_value;
my $acce;
my $title_of_prj;
my $sample_name;
my $dbhost = $opt_H;
my $dbname = $opt_D;
my $infile = $opt_i;
my $pass = $opt_p;
my $driver = $opt_d;
my $user = $opt_u;

my $DBPROFILE = $opt_g ;

print "H= $opt_H, D= $opt_D, u=$opt_u, d=$opt_d, v=$opt_v, t=$opt_t, i=$opt_i  \n";

my $port = '5432';
my ($dbh, $schema);

if ($opt_g) {
    my $DBPROFILE = $opt_g;
    $DBPROFILE ||= 'default';
    my $gmod_conf = Bio::GMOD::Config->new() ;
    my $db_conf = Bio::GMOD::DB::Config->new( $gmod_conf, $DBPROFILE ) ;
    
    $dbhost ||= $db_conf->host();
    $dbname ||= $db_conf->name();
    $driver = $db_conf->driver();
    

    $port= $db_conf->port();
    
    $user= $db_conf->user();
    $pass= $db_conf->password();
}

if (!$dbhost && !$dbname) { die "Need -D dbname and -H hostname arguments.\n"; }
if (!$driver) { die "Need -d (dsn) driver, or provide one in -g gmod_conf\n"; }
if (!$user) { die "Need -u user_name, or provide one in -g gmod_conf\n"; }
#if (!$pass) { die "Need -p password, or provide one in -g gmod_conf\n"; }

my $dsn = "dbi:$driver:dbname=$dbname";
$dsn .= ";host=$dbhost";
$dsn .= ";port=$port";

$schema= Bio::Chado::Schema->connect($dsn, $user, $pass||'', { AutoCommit=>0 });

$dbh=$schema->storage->dbh();

if (!$schema || !$dbh) { die "No schema or dbh is avaiable! \n"; }

print STDOUT "Connected to database $dbname on host $dbhost.\n\n";
#####################################################################################################

my $sth;

my %seq  = (
    db         => 'db_db_id_seq',
    dbxref     => 'dbxref_dbxref_id_seq',
    project        => 'project_project_id_seq',
    project_contact  => 'project_contact_project_contact_id_seq',
    contact => 'contact_contact_id_seq',
    projectprop    => 'projectprop_projectprop_id_seq',
    pub => 'pub_pub_id_seq',	
    project_pub => 'project_pub_project_pub_id_seq',	
    cv         => 'cv_cv_id_seq',
    cvterm     => 'cvterm_cvterm_id_seq',
    dbxrefprop => 'dbxrefprop_dbxrefprop_id_seq',	
    pub_dbxref => 'pub_dbxref_pub_dbxref_id_seq',	
    biomaterial => 'biomaterial_biomaterial_id_seq',
    project_pub => 'project_pub_project_pub_id_seq',
    project_biomaterial => 'project_biomaterial_project_biomaterial_id_seq',
	 );

open (INFILE, "<$infile") || die "can't open file $infile";   #
open (ERR, ">$infile.err") || die "Can't open the error ($infile.err) file for writing.\n";
my $exists_count=0;
my $project_count=0;

my %maxval=();

eval {
    
    #Fetch last database ids of relevant tables for resetting in case of rollback
  
    foreach my $key( keys %seq) {
	my $id_column= $key . "_id";
	my $table =  $key;
	my $query = "SELECT max($id_column) FROM $table";
	$sth=$dbh->prepare($query);
	$sth->execute();
	my ($next) = $sth->fetchrow_array();
	$maxval{$key}= $next;
    }

    #db name for BioProject ids
    my $db= $schema->resultset("General::Db")->find_or_create(
	{ name => 'BioProject' } ); 
    my $db_id = $db->get_column('db_id');

    #cvterm_name for 'primary_submission'. All bioprojects are stored with this default 'primary_submission' type_id ,ToDo:need to add 'Umbrella' cvterm for TopAdmin ProjectType#
    my $submission_cvterm = $schema->resultset('Cv::Cvterm')->create_with(
	{name=>'primary_submission', cv=>'project'});

#Need to think way of adding Project type cvterms for 'Umbrella' in database 
    while (my $line = <INFILE>) {
		
	warn "undefining project $project_count\n";
	$project = undef;
        my $prjna;
	chomp $line;
	if ($line=~ m/(\d+)/) {
	    $prjna= $1;
		
	}else { $prjna=$line;
		}

	
      my $acc_text =get("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=bioproject&id=$prjna&rettype=acc&retmode=text");
       chomp $acc_text;
        $acc_text =~ s/(ID:)(\w+)(.*)//g;
       my @lines = split /\n/, $acc_text;
      foreach my $line1 (@lines) {
	 if ($line1=~ m/(BioProject Accession: )(\w+)(.*)/)
       { 
        $acce = $2;
	print "Project Accession is $acce\n";
        }
}
	if (!$prjna) { next(); }
	
	$dbxref = $schema->resultset("General::Dbxref")->find_or_create(
	    { accession => $acce,
	      db_id => $db_id,
	    });
        

        $project = $dbxref->find_related ('project', {dbxref_id => $dbxref->id})if $dbxref;
	
        
	if(!($project)) { 
	    $project_count++;
	    warn "Creating new project num $project_count\n";
	    $project = $schema->resultset('Project::Project')->new( {} ) ; 
	    $contact = $schema->resultset('Contact::Contact')->new( {} );
            $biomaterial = $schema->resultset('Mage::Biomaterial')->new( {} );            
            $organism = $schema->resultset('Organism::Organism')->new( {} );
            
	    my $message = fetch_project($prjna);
	    
	    if ($message) { message($message,1); }
		print "*******************************************\n";
	    print STDOUT "Storing new project. project id = $prjna\n";
		 print "******************************************\n\n";
 
	
	    $project->insert();
		my $project_id = $project->get_column('project_id');
                my $project_acce =  $project->name($acce);
	    	my @prjcount = ();
	push (@prjcount, $project_acce);
        open FILE, ">", "projects_loaded.txt";	
	foreach my $x(@prjcount)
	{
        print FILE "$x\n";
	}
	close FILE;

	&fetch_sample($prjna);
	if (defined $cvt2)
       {	
	$project->find_or_create_related('projectprops' ,
                                                                { type_id => $cvt2, value => $method_value});
       }

	
            my $dum = $biomaterial->get_column('name');
		 
            
           if ($contact->in_storage)
	{
            $project->find_or_create_related('project_contacts', 
							         { contact_id => $contact->contact_id}); 
        }
              
	         foreach my $some(@publ_ids)	
               {
                $pubID=$some;
                     
             $project->find_or_create_related('project_pubs',
               {
               pub_id => $pubID,     
               });
 		
		}
            @publ_ids = ();
	  
           $biomaterial->insert();

	my $biom_for_project = $biomaterial->find_or_create_related('project_biomaterials', 
											   { project_id => $project_id});											


	}

else  {
            $exists_count++;
            print STDOUT "Project $prjna is already stored in the database. Skipping..\n";
        } 
    }
};	


if($@) {
    print $@;  #The Perl syntax error message from the last eval() operator
    print"Failed; rolling back.\n";
   
    foreach my $key ( keys %seq ) { 
	my $value= $seq{$key};
	my $maxvalue= $maxval{$key} || 0;
	if ($maxvalue) { $dbh->do("SELECT setval ('$value', $maxvalue, true)") ;  }
	else {  $dbh->do("SELECT setval ('$value', 1, false)");  }
    }
    $dbh->rollback();
}else{ 
    print"Succeeded.\n";
    print "Inserted $project_count new projects!\n";
    print "$exists_count projects already exist in the database\n";
    
    if($opt_t) {
        print STDOUT "Rolling back!\n";
	foreach my $key ( keys %seq ) { 
	    my $value= $seq{$key};
	    my $maxvalue= $maxval{$key} || 0;
	    
	    if ($maxvalue) { $dbh->do("SELECT setval ('$value', $maxvalue, true)") ;  }
	    else {  $dbh->do("SELECT setval ('$value', 1, false)");  }
	}
	$dbh->rollback();
    }else {
        print STDOUT "Committing...\n";
        $dbh->commit();
    }
}

close ERR;
close INFILE;


sub message {
    my $message=shift;
    my $err=shift;
    if ($opt_v) {
	print STDOUT $message. "\n";
    }
    print ERR "$message \n" if $err;
}



sub sanitize {
    my $string = shift;
    $string =~ s/^\s+//; #remove leading spaces
    $string =~ s/\s+$//; #remove trailing spaces
    return $string;
}


sub create_projectprops {
    my ($self, $props, $opts) = @_;
    
    # process opts
    $opts ||= {};
    $opts->{cv_name} = 'project'
	unless defined $opts->{cv_name};
    
    return Bio::Chado::Schema::Util->create_properties
	( properties => $props,
	  options    => $opts,
	  row        => $self,
	  prop_relation_name => 'projectprops',
	);
}

sub reset_sequences {
    my %seq=@_;
    my %maxval=@_;
    #reset sequences
    foreach my $key ( keys %seq ) { 
	my $value= $seq{$key};
	my $maxvalue= $maxval{$key} || 0;
	if ($maxvalue) { $dbh->do("SELECT setval ('$value', $maxvalue, true)") ;  }
	else {  $dbh->do("SELECT setval ('$value', 1, false)");  }
    }
}

##############################################################################
#IMPORTANT big subroutine 'fetch_project' called to parse bioproject XML data#
##############################################################################

sub fetch_project {
    
    my $accession=shift;
    my $project_xml = get("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=bioproject&id=$accession&rettype=xml&retmode=text");
  	print "project_xml is : $project_xml \n"; 
    $pt1 = XML::XPath->new( xml => $project_xml);
    my $organization_bool = $pt1->exists('//Submission/Description/Organization/Name'); #check for existence of this optional element
    my $organism_bool = $pt1->exists('//ProjectTypeSubmission/Target/Organism/OrganismName');#check for existence of this optional element
    my $data_type_bool = $pt1->exists('//DataType'); 
    my $umbrella_bool = $pt1->exists('//ProjectType/ProjectTypeTopAdmin');
	

   my $pub_bool = $pt1->exists('//Project/ProjectDescr/Publication');
   if ($pub_bool == 1)
	{

	print "Publication exists for this Project \n\n";
        my $nodeset = $pt1->find('//Project/ProjectDescr/Publication');  	
        open FILE,">","pubids.txt" or die $!;  	
	foreach my $node ($nodeset->get_nodelist)
	{
	my $pubid = $node->getAttribute('id'); #gets pubmed id

	print FILE "$pubid\n";
	
	#system call to an external perl script to load publications data from PubMed into 'pub' table of Chado#
	#IMPORTANT: Make sure this script named 'gmod_bulk_load_pubmed_adf.pl' is always present in the directory when running this code 
	system ("gmod_bulk_load_pubmed_adf.pl -D chado_with_goa_and_project -H butler -d Pg -u adf -p changeme -i ./pubids.txt -v");
        my $query1 = "SELECT pub_id FROM pub_dbxref where dbxref_id IN (select dbxref_id from dbxref where accession='$pubid')"; 
	my $sth1;
	$sth1=$dbh->prepare($query1);
        $sth1->execute();
 				
		while (my $row_id = $sth1->fetchrow_array())
         {      
                push(@publ_ids, $row_id);
	        
      	} 
     }

close FILE;

}


if ($data_type_bool == 1)
{
   eval {

	if ($organization_bool == 1 && $organism_bool == 1){
        my $twig=XML::Twig->new(
        
              twig_handlers   =>
            {
                'Project/ProjectDescr/Title'    => \&name,  # ele/ele searches for this matching path #if it starts with /ele/ele it starts search at root node 
                 'Project/ProjectDescr/Description'   => \&description,
		'Submission/Description/Organization/Name' => \&proj_contact,
               'ProjectTypeSubmission/Target/Organism/OrganismName' => \&organism, 
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
               'DataType' => \&proj_type,      
		'ProjectType/ProjectTypeSubmission/Method' => \&method,
		},
           
            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
	}
          elsif ($organization_bool == 0 && $organism_bool == 1){
	my $twig=XML::Twig->new(
        
              twig_handlers   =>
            {
                'Project/ProjectDescr/Title'    => \&name,   
                 'Project/ProjectDescr/Description'   => \&description,
               'ProjectTypeSubmission/Target/Organism/OrganismName' => \&organism, 
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
		'DataType' => \&proj_type,
		'ProjectType/ProjectTypeSubmission/Method' => \&method,
              },
            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
        } 

     elsif ($organization_bool == 1 && $organism_bool == 0)
	{
	my $twig=XML::Twig->new(

              twig_handlers   =>
            {
               'Project/ProjectDescr/Title'    => \&name,
                 'Project/ProjectDescr/Description'   => \&description,
                'Submission/Description/Organization/Name' => \&proj_contact,
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
              'DataType' => \&proj_type,
	      'ProjectType/ProjectTypeSubmission/Method' => \&method,
		},
            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
        }
 
else {

my $twig=XML::Twig->new(

              twig_handlers   =>
            {
               'Project/ProjectDescr/Title'    => \&name,
                 'Project/ProjectDescr/Description'   => \&description,
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
              'DataType' => \&proj_type,
	      'ProjectType/ProjectTypeSubmission/Method' => \&method,
		},
            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
        }



  };

}


else
 {


eval {

        if ($organization_bool == 1 && $organism_bool == 1){
        my $twig=XML::Twig->new(

              twig_handlers   =>
            {
                'Project/ProjectDescr/Title'    => \&name,
                 'Project/ProjectDescr/Description'   => \&description,
                'Submission/Description/Organization/Name' => \&proj_contact,
               'ProjectTypeSubmission/Target/Organism/OrganismName' => \&organism,
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
               'Data' => \&undefined_type,
                'ProjectType/ProjectTypeSubmission/Method' => \&method,
                },

            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
        }
          elsif ($organization_bool == 0 && $organism_bool == 1){
        my $twig=XML::Twig->new(

              twig_handlers   =>
            {
                'Project/ProjectDescr/Title'    => \&name,
                 'Project/ProjectDescr/Description'   => \&description,
               'ProjectTypeSubmission/Target/Organism/OrganismName' => \&organism,
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
                'Data' => \&undefined_type,
		'ProjectType/ProjectTypeSubmission/Method' => \&method,
              },
            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
        }

     elsif ($organization_bool == 1 && $organism_bool == 0)
        {
        my $twig=XML::Twig->new(

              twig_handlers   =>
            {
                'Project/ProjectDescr/Title'    => \&name,
                 'Project/ProjectDescr/Description'   => \&description,
                'Submission/Description/Organization/Name' => \&proj_contact,
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
               'Data' => \&undefined_type,
              'ProjectType/ProjectTypeSubmission/Method' => \&method,
                },
            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
        }

else {

my $twig=XML::Twig->new(

              twig_handlers   =>
            {
                'Project/ProjectDescr/Title'    => \&name,
                 'Project/ProjectDescr/Description'   => \&description,
               'ProjectType/ProjectTypeSubmission/Target' => \&material,
               'Data' => \&undefined_type,
              'ProjectType/ProjectTypeSubmission/Method' => \&method,
                },
            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
        $twig->print;
        }

  };

}

#For future work, to consider Umbrella Project##

#if ($data_type_bool == 0 && $umbrella_bool == 1)
#{
#print "\n************It is an Umbrella project *********************\n\n"
#
#        my $twig=XML::Twig->new(
#
#              twig_handlers   =>
#            {
#                'Project/ProjectDescr/Title'    => \&name_umbrella,
 #                'Project/ProjectDescr/Description'   => \&description_umbrella,
 #               'Submission/Description/Organization/Name' => \&proj_contact,
 #              'ProjectTypeTopAdmin/Organism/OrganismName' => \&organism,
#
#                },
#
#            pretty_print => 'indented',  # output will be nicely formatted
#            ) || die($!);
#        $twig->parse($project_xml) || die("twig parse failed: " . $!); # build it
#        $twig->print;
#
#}
    
if($@) {
        my $message= "Error in transaction or NCBI server seems to be down. Please check your input for accession $accession or try again later.\n $@";
        return $message;
    }else { return undef ; }


}
# handler is always called with just 2 parameters: the twig and the element



#############################################
#Testing: Subroutine to fetch Biosample data#
#############################################

sub fetch_sample
{
my $accession_sample=shift;
my $biosample_xml = get("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/elink.fcgi?dbfrom=bioproject&db=biosample&id=$accession_sample&linkname=bioproject_biosample&rettype=xml&retmode=text");
    
    print "________________Printing biosample xml______________\n";
    print "$biosample_xml\n\n";
    $pt2 = XML::XPath->new(xml => $biosample_xml);
    my $biosample_bool = $pt2->exists('//Link/Id'); #Link/Id is a path in xml of biosample-bioproject eutil linkname

    
    if ($biosample_bool == 1)
        {
        print "Biosample exists for this Project \n\n";
        open FILE,">","bioids.txt" or die $!;
	foreach my $node ($pt2->findnodes('//Link/Id'))
	{
	my $sample_id = $node->string_value; #gets sample id
        print FILE "$sample_id\n";
	
       }	
      close FILE;

open FILE,"<","bioids.txt" or die $!;

while (my $line2 = <FILE>)
{
my $samn;
chomp $line2;
if ($line2=~ m/(\d+)/) {
         $samn= $1;
print "Sample id is : $samn \n\n";

        }else { 
		$samn=$line2;
		print "Else sample id is : $samn \n\n";
                }
my $sample_xml = get("http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=biosample&id=$samn&rettype=xml&retmode=text");

print $sample_xml;

#################################################################################################################
#        ****My notes about XML Twig Handlers
# /root/elt/subelt	triggers the handler for elements matching this exact path path, starting from the root #
# elt/subelt	triggers the handler for element matching this path						#
# elt	triggers the handler for all gi elements								#
# _default_	triggers the handler if no other handler has been trigger					#
#														#
#################################################################################################################
eval {  

        my $twig_s=XML::Twig->new(
        
          twig_roots   =>
            {
            'BioSampleSet/BioSample' => \&accession_s,#6
                'Description/Title'   => \&description_s, #2
		'Description/Organism'    => \&organism_s, #3
                'Owner/Name' => \&contact_s,#4
                'Attribute'   => \&attribute,#5 #populates biomaterialprop table #to search all elements called Attribute
		'Ids/Id' => \&other_dbs,  #1 (This number from #1-#6 represent the order in which these subroutines are called based on the tree)
		},


	            twig_handlers =>
            { },

            pretty_print => 'indented',  # output will be nicely formatted
            ) || die($!);
        $twig_s->parse($sample_xml) || die("twig_s parse failed: " . $!); # build it
        $twig_s->print;
        }; warn $@ if $@;


}

 close FILE;
}
}

##########################################
#BioSample subroutines to parse XML      #
##########################################

sub accession_s
{
my ($twig_s, $elt)= @_;
my $acce_s = $elt->att('accession');
my $sample_uid = $elt->att('id');

print "Accession of biosample is : $acce_s \n\n";

my $db_s= $schema->resultset("General::Db")->find_or_create(
        { name => 'BioSample' } );
 my $db_id_s = $db_s->get_column('db_id');
print "db_id for BioSample db is : $db_id_s \n\n";

if (defined $acce_s)
{
$dbxref_s = $schema->resultset("General::Dbxref")->find_or_create(
            { accession => $acce_s,
              db_id => $db_id_s,
            });
}
else 
{
$dbxref_s = $schema->resultset("General::Dbxref")->find_or_create(
            { accession => $sample_uid,
              db_id => $db_id_s,
            });
}
$a = $dbxref_s->get_column('dbxref_id');

$aa = $dbxref_s->get_column('accession');
$biomaterial_s = $schema->resultset('Mage::Biomaterial')->find_or_new({
		name => $aa,
	description => $desc_s,
	biosourceprovider_id => $c,
	dbxref_id => $a,
	taxon_id => $b,
});

if (defined $stk_id)
{
$biomaterial_s->stock_id($stk_id);
}

if (!$biomaterial_s->in_storage) {
$biomaterial_s->insert;
}

$stk_id = undef;


my $project_biom = $biomaterial_s->find_or_create_related('project_biomaterials', {project_id => $project_id});


foreach my $arra(@getdbx_ids)
{
#print "Sec dbxref: $arra \n\n";
my $biodbxref = $biomaterial_s->find_or_create_related('biomaterial_dbxrefs', {dbxref_id => $arra});

} 
@getdbx_ids = ();

#add new prop 
if (@ele_a != 0)
{
foreach  (my $i = 0; $i <= @ele_a-1; $i++ ) 
		{
		my $type_a = $cvta[$i];
		my $value_a = $ele_a[$i];

my $bioprop_a = $biomaterial_s->find_or_create_related('biomaterialprops' ,
                                                            { rank => 0, type_id => $type_a, value => $value_a});
}
	
}
if (@ele_b !=0)
{
foreach  (my $i = 0; $i <= @ele_b-1 ; $i++)  
    {
	my $type_b = $cvtb[$i];
                my $value_b = $ele_b[$i];

my $bioprop_b = $biomaterial_s->find_or_create_related('biomaterialprops' ,
                                                             { rank => 0, type_id => $type_b, value => $value_b}, {key=> 'biomaterialprop_c1'});

    }
}
@cvta = ();
@cvtb = ();
@ele_a = ();
@ele_b = ();
$twig_s->purge;

}





sub organism_s{

my ($twig_s, $elt) = @_;
my $org_s = $elt->att('taxonomy_name');

my $genus = substr( $org_s, 0, index( $org_s, ' ' ) );
my $species = substr( $org_s, index( $org_s, ' ' ) + 1 );

my $first = substr($genus, 0, 1);
my $abbr = "$first.$species";

if ($genus ne "" && $species ne "")
{
my $abbr = "$first.$species";

$organism_s = $schema->resultset('Organism::Organism')->find_or_new({ genus => $genus, species => $species});
           unless ($organism_s->in_storage) {
                                             print "**Adding new biomsaple's organism $genus $species \n\n";
                                             $organism_s->genus($genus);
                                             $organism_s->species($species);
                                             $organism_s->abbreviation($abbr);

                    $organism_s->insert();
                }

}

 $b = $organism_s->get_column('organism_id');

$twig_s->purge; #frees the memor

}


sub contact_s
{
my ($twig_s, $elt) = @_;
my $cont_s = $elt->text;
$contact_s = $schema->resultset('Contact::Contact')->find_or_new({ name => $cont_s});  #contact name is unique
           unless ($contact_s->in_storage) {
                                            print "**Adding new biosample's contact: $cont_s \n\n";
                                                 $contact_s->name($cont_s);

						$contact_s->insert();
}
$c = $contact_s->get_column('contact_id');

$twig_s->purge;
}

sub description_s
{
my ($twig_s, $elt) = @_;
$desc_s = $elt->text;
$project_id = $project->get_column('project_id');

print "Sample name is : $sample_name \n\n";
  
      
$twig_s->purge;
}

sub attribute
{
my ($twig_s, $elt) = @_;
my @ele_stock = ();
my $attr1 = $elt->att('dictionary_name');
my $attr2 = $elt->att('harmonized_name');
my $attr_simple = $elt->att('attribute_name');
push(@ele_stock, $attr_simple);
if (defined $attr1 && defined $attr2) #checks if both dict and harmonized name is present#
{

if (($attr1 ne 'strain' || $attr2 ne 'strain') || ($attr1 ne 'cultivar' || $attr2 ne 'cultivar'))
{
my $element_a = $elt->text;
$sample_cvterm = $schema->resultset('Cv::Cvterm')->create_with({name=>$attr2, cv=>$attr1});
my $cv = $sample_cvterm->get_column('cv_id');
$cvt_a = $sample_cvterm->get_column('cvterm_id');
print "Sample attribute is cv:$attr1 cvterm:$attr2 \n\n";
push(@ele_a, $element_a);
push(@cvta, $cvt_a);
}
}
else
{
my $element_b = $elt->text;
my $attr3 = $elt->att('attribute_name');
$sample_cvterm = $schema->resultset('Cv::Cvterm')->create_with({name=>$attr3, cv=>'ncbi_biosample'});
my $cv = $sample_cvterm->get_column('cv_id');
$cvt_b = $sample_cvterm->get_column('cvterm_id');
push(@ele_b, $element_b);
push(@cvtb, $cvt_b);

print "New attribute_name attribute created- cv_id: $cv, cvterm_id: $cvt_b \n\n";

print "Sample attribute is cvterm:$attr3 \n\n";

}


foreach my $yy(@ele_stock)
{

print "Latest attribute name testing values are : $yy \n";
if ($yy eq 'strain' || $yy eq 'cultivar')
{
print "Populating strain/cultivar in stock table....attr c value \n\n"; #treating strain and cultivar as same attribute to insert in stock table#
my $ele_c = $elt->text;
my $attr_cvterm = $schema->resultset('Cv::Cvterm')->create_with({name=>'strain', cv=>'ncbi_biosample'});
my $type_c = $attr_cvterm->get_column('cvterm_id');
my $b = $organism_s->get_column('organism_id');
print "Cultivar or Strain's name is : $ele_c \n";
$stock = $schema->resultset('Stock::Stock')->find_or_create({name=>$ele_c, uniquename=>$ele_c, type_id=>$type_c, organism_id=>$b, description=>$yy});

$stk_id = $stock->get_column('stock_id');
print "Stock_id to insert is : $stk_id \n";
}
}
$twig_s->purge;
}


sub other_dbs{
	my ($twig_s, $elt) = @_;
	my $id_value = $elt->text;
	my $sec_db = $elt->att('db');
        my $s_name = $elt->att('db_label');

#db name for secondary dbs for secondary dbxref##


if (defined $sec_db)
{
   print "Secondary database name is $sec_db \n\n";
   
 my $db_sec = $schema->resultset("General::Db")->find_or_new({ name => "$sec_db" });
 	unless($db_sec->in_storage)
	{
	print "db name of sec db is : $sec_db \n\n";
	$db_sec->name($sec_db);	
	$db_sec->insert();
	}
    		my $db_id_sec = $db_sec->get_column('db_id');
    
  		   my $dbxref_sec = $schema->resultset("General::Dbxref")->find_or_new(
            	{ accession => "$id_value",
              	db_id => "$db_id_sec",
            	});

 	unless($dbxref_sec->in_storage)
  	{ 
	
	print "Adding new dbxref accession $id_value for secondary db $sec_db \n\n";
	        $dbxref_sec->accession($id_value);
		$dbxref_sec->db_id($db_id_sec);

			$dbxref_sec->insert();
       } 
       my $dbx_sec = $dbxref_sec->get_column('dbxref_id'); 
	 push(@getdbx_ids, $dbx_sec);        
       	

}
elsif (defined $s_name)
{
$sample_name = $id_value;

print "Sample name is db_label : $sample_name\n\n";

}

else
{
print " Attribute db not present for this <Id> element \n\n";
}

$twig_s->purge;  


}
 

    
 
#############################################
#Functions for parsing the XML of BioProject#          
############################################

sub name
 {
      my ($twig, $elt)= @_;
      $title_of_prj = $elt->text;
print "Title of Project is : $title_of_prj";     
 $twig->purge; #frees the memory
 }




sub name_umbrella
{
     my ($twig, $elt)= @_;
     $title_of_umbrella = $elt->text;
print "Title of Project is : $title_of_umbrella";

my $project_cvte = $schema->resultset('Cv::Cvterm')->create_with({name=>'umbrella_project', cv=>'ncbi_bioproject'});
my $cv_u = $project_cvte->get_column('cv_id');
my $cvt_u = $project_cvte->get_column('cvterm_id');

print "Project type is : $cvt_u \n\n";

 $project->type_id($cvt_u);
 $twig->purge; #frees the memory
}


sub description_umbrella
{
 my ($twig, $elt)= @_;
    my $description = $elt->text;
                                          print "**Adding project description:Title: $title_of_umbrella\n Description: $description \n\n";
                $project->name($acce);   #changed name of project as its accession eg PRJNAXXXX                      
                $project->description("Title: $title_of_umbrella, Description: $description");
            my $dbx = $dbxref->get_column('dbxref_id');
            $project->dbxref_id($dbx);

                        $twig->purge; #frees the memory
   }







 
#sub name {    #COMMENT OUT 	THIS NAME SUB 	to create new name sub for project name having only accession of project eg PRJNAXXXX ###
#    my ($twig, $elt)= @_;
#    my $name = $elt->text; #$elt returns tag of the element 
#    my $name_count = 0;
#    $project = $schema->resultset('Project::Project')->find_or_new({ name => "$name"});
#   	
#	if ($project->in_storage) { 
#				   $name_count++;
#			           #$project->name("$name | count:$name_count");
#				   $project = $schema->resultset('Project::Project')->find_or_new({ name => "$name | count:$name_count"});					
#				   #$name_count++;
#					while ($project->in_storage)
#					{
#					$name_count++;
#					$project = $schema->resultset('Project::Project')->find_or_new({ name => "$name | count:$name_count"});
#					}
#					print "***Adding duplicate name with incremented count\n\n";
#				   $project->name("$name | count:$name_count");
##					
#				}
#                                 			
#			else 
#				{
#				print "**Adding new name:$name\n\n"; 
#				 $project->name("$name");
#				}
#
#
#                   $twig->purge; #frees the memory
#            }


sub description {
    my ($twig, $elt)= @_;
    my $description = $elt->text;
                                          print "**Adding project description:Title: $title_of_prj\n Description: $description \n\n";
                $project->name($acce);   #changed name of project as its accession eg PRJNAXXXX                      
		$project->description("Title: $title_of_prj, Description: $description");
            my $dbx = $dbxref->get_column('dbxref_id');   
            $project->dbxref_id($dbx);

			$twig->purge; #frees the memory
   }



#if element path does not exist then its subroutine is not executed##
# w/o calling a subrouting in fetch_project simply define $bool and execute insert of 'undefined value' if it is 0

sub proj_contact {
my ($twig, $elt)= @_;
my $cont = $elt->text;

 $contact = $schema->resultset('Contact::Contact')->find_or_new({ name => $cont});  #contact name is unique
           unless ($contact->in_storage) {  
					    print "**Adding new contact: $cont \n\n";
                                             $contact->name($cont);
						$contact->insert();
}
				
#print "Contact name already exists or not provided for project...Skipping\n\n";
my $c = $contact->get_column('contact_id');
print "Contact id is : $c \n\n";
$biomaterial->biosourceprovider_id($c);
#$project->find_or_create_related('project_contacts', { contact_id => $contact->contact_id}); 
   
$twig->purge;
}


sub organism {
my ($twig, $elt)= @_;
my $org = $elt->text;
my @token = split(/ /,$org);

my $genus = $token[0];
my $species = $token[1];
my $first = substr($genus, 0, 1);
#my $abbr = "$first.$species";
if ($genus ne "" && $species ne "")
{
my $abbr = "$first.$species";

$organism = $schema->resultset('Organism::Organism')->find_or_new({ genus => $genus, species => $species});
           unless ($organism->in_storage) {
                                             print "**Adding new organism $genus $species \n\n";
                                             $organism->genus($genus);
					     $organism->species($species);
					     $organism->abbreviation($abbr);  		
                                         
                    $organism->insert();		
		} 

}
$twig->purge; #frees the memor

}



sub material{

my ($twig, $elt)= @_;
my $name = $elt->att('material');
my $ba = $organism->get_column('organism_id');


          $biomaterial = $schema->resultset('Mage::Biomaterial')->find_or_new({ name => "$acce-$name"}); #biomaterial name is unique
           unless ($biomaterial->in_storage) {
                                              print "**Adding new material: $acce-$name\n\n";
	                                        $biomaterial->name("$acce-$name");
						$biomaterial->taxon_id($ba);
						$biomaterial->description($name);
}
	$twig->purge;

}



sub proj_type{

my ($twig, $elt)= @_;
my $prj_type = $elt->text;

$project_cvterm = $schema->resultset('Cv::Cvterm')->create_with({name=>$prj_type, cv=>'ncbi_bioproject'});
my $cv = $project_cvterm->get_column('cv_id');
 my $cvt = $project_cvterm->get_column('cvterm_id');

print "Project type is: $prj_type \n\n";
			
$project->type_id($cvt);

}




sub undefined_type  {

my ($twig, $elt)= @_;
my $name = $elt->att('data_type'); #can use this attribute for data type eg. eExpression in cases where <DataType> elememt is absent but <Data> is present.

my $pseudo = "undefined";
$project_cvterm = $schema->resultset('Cv::Cvterm')->create_with({name=>$pseudo, definition=>'Unspecified Data Type for BioProject', cv=>'ncbi_bioproject'});
my $cv = $project_cvterm->get_column('cv_id');
my $cvt = $project_cvterm->get_column('cvterm_id');

print "Project type is: $pseudo \n\n";

$project->type_id($cvt);

}



#for using method_type as a property in projectprop

sub method{

my ($twig, $elt)= @_;
$method_value = $elt->att('method_type');


my $method_cvterm = $schema->resultset('Cv::Cvterm')->create_with({name=>'method_type', cv=>'ncbi_bioproject'});
$cvt2 = $method_cvterm->get_column('cvterm_id');

print "Method type value is: $method_value \n\n";

}










