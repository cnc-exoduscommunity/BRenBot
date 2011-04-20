#!/usr/bin/perl



#use strict;
#use warnings;

unless(opendir(DATADIR, "plugins/"))
{ print "Unable to open plugins folder\n"; }

my @xmlfiles = grep(/\.xml$/i,readdir(DATADIR));

foreach (@xmlfiles)
{
	my $file = $_;
	
	print "Fixing XML entries in $file\n";
	
	fixXMLEntities ( $file );
}




# Function to scan an XML file for <, > and & in text tags and substitute it properly.
sub fixXMLEntities
{
	my $xmlFile = shift;
	my $newFile = "";
	
	open XMLFILE, "plugins/".$xmlFile;
	while ( <XMLFILE> )
	{
		if ( $_ =~ m/^(\s*\<\S+\s+\S+=\")(.+)(\"\/\>)$/i )
		{
			my $prefix = $1;
			my $value = $2;
			my $suffix = $3;
			
			$value =~ s/&(?!(gt;|lt;|apos;|quot;|amp;))/&amp;/g;
			$value =~ s/>/\&gt\;/g;
			$value =~ s/\</\&lt\;/g;
			
			$newFile .= $prefix.$value.$suffix."\n";
		}
		else
		{
			$newFile .= $_;
		}
	}
	close XMLFILE;
	
	open XMLFILE,, '>'."plugins/".$xmlFile;
	print XMLFILE $newFile;
	close XMLFILE;
}