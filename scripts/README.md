Synopsis
========

This is a documentation for a Perl script gmod_bulk_load_bioproject.pl

BioProject, BioSample and PubMed are NCBI databases and this script is an attempt to fetch data from BioProject and its related BioSample and PubMed data by parsing its XML and using NCBI E-utilities.

Currently, it is used to load Primary Submission Type projects and future work will involve loading of Umbrella Type projects.

## RESOURCES

1] Glossary help for BioProject available at: https://www.ncbi.nlm.nih.gov/books/NBK54364/

2] Glossary help for BioSample avaiable at: http://www.ncbi.nlm.nih.gov/books/NBK169436/

3] Entrez e-utils: http://www.ncbi.nlm.nih.gov/books/NBK25501/


## DATA LOADING

This script is used to parse XML to obtain metadata from NCBI-BioProject and there related BioSample and PubMed data from NCBI.

Please run following at command-line by providing correct options for your database connection-

	gmod_bulk_load_bioproject.pl -D chado_database_name -H butler -d database_driver -u user_name -p password -i /path/to/input/file_with_Project_UIDs 

We are currently using final database named 'chado_with_goa_and_project' which is the latest and updated copy of our chado database content.

	To load data : gmod_bulk_load_bioproject.pl -D chado_with_goa_and_project -H butler -d Pg -u user_name -p password -i /path/to/input/file_with_Project_UIDs

Or use -g option for database connection if using GMOD profile.

### Important 

Also, make sure the additional script gmod_bulk_load_pubmed_adf.pl(for publications) which is called by this bioproject script is present in the directory or your path.


### Input file (-i)

Input file is a simple text file with list of UIDs of BioProject that you want to load in database in numeric format- For example: 178155

(Please note: BioProject accessions comes in three flavor PRJNA/PRJDB/PRJEB. While UID for accessions beginning with PRJNA are same, they differ for project starting with PRJDB or PRJEB, that is why we have decided to use only UIDs in the input file for correctness)


### Bio::Chado::Schema

Add this to PATH of ~/.bash_profile /sw/tools/git/cv/bin

For using this script you will need modified version of BCS which is located in this git directory /lis_chado/bioperlstuff.

Add the path of your git clone directory before /lis_chado/bioperlstuff and add it to  ~/.bash_profile. For eg. /home/peu/my_git_dir/lis_chado/bioperlstuff

After these two changes to set your paths, source your bash profile by running this . ~/.bash_profile

You can either export it-
export PERL5LIB=/path_to_your_home_git/lis_chado/bioperlstuff

OR
You can add them to the ~/.bash_profile to make it always available when you log-in.


## CHADO TABLES

### project table:

Name: Accession of BioProject

Description: Description of BioProject provided

Type_id:  It indicates Project data type- A general label indicating the primary study goal. These are only relevant for Primary submission projects (not Umbrella projects)

	Case I:  If <DataType> elemet is present in XML then the value is used at type_id of project by creating a cvterm for it under controlled vocabulary of 'ncbi_bioproject'

	Case II: If <DataType>  is not present in XML then it is regarded as ‘undefined’ project data type



### projectprop table

This table is used to store method_type attribute of the project from Project’s Attributes section.

Method: Indicate the general approach used to obtain data.
•	Sequence: select Sequence if any sequence data is generated
•	Array: select Array if that is the primary method and no sequence data is submitted
•	Mass Spectrometry: select Mass Spectrometry if that is the primary method
•	Other: specify the method.



### contact table

This table is populated with information of Submitter of Project

### project_contact table

This table links project to its submitter information (contact table)

### pub table

Fetches and Stores PubMed publications cited by its BioProject by calling other script from within this program-

gmod_bulk_load_pubmed_adf.pl [use same database connection in the main script that is used while running project script]

Note: Some projects have publications and some dont. 

uniquename in Pub table consist of its PMID and Title in the format "PMID:Title"

### project_pub

This table is a relation between project and its associated publications. 

### biomaterial table

This table is important and it is used to store sample's metadata from BioSample database. 
This script automatically fetches the list of biosamples that are related to a bioproject and then load their metadate from respective XML into biomaterial table and related tables.
The primary dbxref of a biomaterial is stored in this table for 'BioSample' db in chado. A new column added in this table is stock_id which refers to a strain/cultivar of that sample.

### biomaterialprop table

This table stores all the attributes of a biosample and the cvterms are created for each attribute.

For example(Attributes):

tissue
age
genotype
treatment
source_name 
etc.

### biomaterial_dbxref:

This table is used to store secondary dbxref of a biomaterial that points to a biosample's identifier in databases other than BioSample, like SRA and GEO.

### project_biomaterial

This is a new table created in-house and does not come with Chado schema. It is created for showing a relation or linkage between a project and all of its samples (biomaterials)   
**Please refer to SQL document to know how a new table is created in chado and its respective BCS module created under /Bio/Chado/Schema directory.
 
### stock table:

This table is used to store strain/cultivar name of a species for a biomaterial(sample). 

### cv table
A Controlled Vocabulary entry is automatically made for 'ncbi_bioproject' by this script

### cvterm table
cvterms are created and stored for attributes of biosample. For example: tissue

### dbxref table 
This table is used to store all accessions



## ADDITIONAL

Please refer to SQL query page for looking at the ALTER queries and CREATE TABLE query used to make change in Chado Schema

More stuff to add...

 




