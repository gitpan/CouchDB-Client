use inc::Module::Install 0.64;

name 'CouchDB-Client';

perl_version '5.6';
license 'perl';
all_from 'lib/CouchDB/Client.pm';

requires 'LWP::UserAgent';
requires 'Exception::Class';
requires 'HTTP::Request';
requires 'URI::Escape';
requires 'MIME::Base64';

WriteAll;
