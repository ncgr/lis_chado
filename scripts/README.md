This is a documentation for a Perl script gmod_load_project.pl

BioProject, BioSample and PubMed are NCBI and databases and this script is an attempt to fetch data from BioProject and its related BioSample and PubMed data via its XML parsind and NCBI E-utilities.

RESOURCES:

1] Glossary help for BioProject available at: https://www.ncbi.nlm.nih.gov/books/NBK54364/

2] Glossary help for BioSample avaiable at: http://www.ncbi.nlm.nih.gov/books/NBK169436/

3] Entrez e-utils: http://www.ncbi.nlm.nih.gov/books/NBK25501/


DATA LOADING

This script is used to parse XML to obtain metadata from NCBI-BioProject and there related BioSample and PubMed data from NCBI.

Please run following at command-line by providing correct options for database connection-

gmod_load_bioproject.pl -D <chado_database_name> -H <butler> -d Pg -u <user name> -p <password> -i /path/to/input/file_with_Project_UIDs 

Or use -g option if using GMOD profile.

Input file (-i) :

Input file is a simple text file with list of UIDs of BioProject that you want to load in database in numeric format- For example: 178155

(Please note: BioProject accessions come in three flavor PRJNA/PRJDB/PRJEB. While UID for accessions beginning with PRJNA are same, they differ for project starting with PRJDB or PRJEB, that is why we have decided to use only UIDs in the input file)


Bio::Chado::Schema :

For using this script you will need modified version of BCS which is located in the directory 

You can either export it-
export PERL5LIB=/home/peu/git_chado_peu/lis_chado/bioperlstuff
OR
You can add this to the ~/.bash_profile to make it always available when you log-in.


CHADO TABLES

project table:

Name: Accession of BioProject

Description: Description of BioProject provided

Type_id:  It indicates Project data type- A general label indicating the primary study goal. These are only relevant for Primary submission projects (not Umbrella projects)

	Case I:  If <DataType> elemet is present in XML then the value is used at type_id of project by creating a cvterm for it under controlled vocabulary of 'ncbi_bioproject'

	Case II: If <DataType>  is not present in XML then it is regarded as ‘undefined’ project data type



projectprop table:

This table is used to store method_type attribute of the project from Project’s Attributes section.

Method: Indicate the general approach used to obtain data.
•	Sequence: select Sequence if any sequence data is generated
•	Array: select Array if that is the primary method and no sequence data is submitted
•	Mass Spectrometry: select Mass Spectrometry if that is the primary method
•	Other: specify the method.



contact table:

This table is populated with information of Submitter of Project

project_contact table:

This table links project to its submitter information (contact table)

pub:

Fetches and Stores PubMed publications cited by its BioProject by calling other script from within this program-

gmod_bulk_load_pubmed_adf.pl [use same database connection in the main script that is used while running project script]

Note: Some projects have publications and some dont. 

uniquename in Pub table consist of its PMID and Title in the format "PMID:Title"

project_pub:

This table is a relation between project and its associated publications. 

biomaterial table:

This table is important and it is used to store sample's metadata from BioSample database. 
This script automatically fetches the list of biosamples that are related to a bioproject and then load their metadate from respective XML into biomaterial table and related tables.
Also, the primary dbxref of a biomaterial is stored in this table for 'BioSample' db in chado. 


biomaterialprop table:

This table stores all the attributes of a biosample and the cvterms are created for each attribute.

For example(Attributes):

tissue
age
genotype
treatment
source_name 
etc...

biomaterial_dbxref:

This table is used to store secondary dbxref of a biomaterial that points to a biosample's identifier in databases other than BioSample, like SRA and GEO.

project_biomaterial:

This is a new table created in-house and does not come with Chado schema. It is created for showing a relation or linkage between a project and all of its samples (biomaterials)   
**Please refer to SQL document to know how a new table is created in chado and its respective BCS module created under /Bio/Chado/Schema directory.

 
stock table:












*****Bio::Chado::Schema (To write its location for user to use that copy, and create a seperate doc for all ALTER SQL queries that were run on chado -to add new table and columns)

Input file:




 




