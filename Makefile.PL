use inc::Module::Install 0.64;

name 'CouchDB-Client';

perl_version '5.006';
license 'perl';
all_from 'lib/CouchDB/Client.pm';

requires 'JSON::Any' => '1.17';
requires 'LWP::UserAgent';
requires 'HTTP::Request';
requires 'URI::Escape';
requires 'MIME::Base64';

WriteAll;
