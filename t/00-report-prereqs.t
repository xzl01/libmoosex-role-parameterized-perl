#!perl

use strict;
use warnings;

# This test was generated by Dist::Zilla::Plugin::Test::ReportPrereqs 0.027

use Test::More tests => 1;

use Module::Metadata;
use File::Spec;

# from $version::LAX
my $lax_version_re =
    qr/(?: undef | (?: (?:[0-9]+) (?: \. | (?:\.[0-9]+) (?:_[0-9]+)? )?
            |
            (?:\.[0-9]+) (?:_[0-9]+)?
        ) | (?:
            v (?:[0-9]+) (?: (?:\.[0-9]+)+ (?:_[0-9]+)? )?
            |
            (?:[0-9]+)? (?:\.[0-9]+){2,} (?:_[0-9]+)?
        )
    )/x;

# hide optional CPAN::Meta modules from prereq scanner
# and check if they are available
my $cpan_meta = "CPAN::Meta";
my $cpan_meta_pre = "CPAN::Meta::Prereqs";
my $HAS_CPAN_META = eval "require $cpan_meta; $cpan_meta->VERSION('2.120900')" && eval "require $cpan_meta_pre"; ## no critic

# Verify requirements?
my $DO_VERIFY_PREREQS = 1;

sub _max {
    my $max = shift;
    $max = ( $_ > $max ) ? $_ : $max for @_;
    return $max;
}

sub _merge_prereqs {
    my ($collector, $prereqs) = @_;

    # CPAN::Meta::Prereqs object
    if (ref $collector eq $cpan_meta_pre) {
        return $collector->with_merged_prereqs(
            CPAN::Meta::Prereqs->new( $prereqs )
        );
    }

    # Raw hashrefs
    for my $phase ( keys %$prereqs ) {
        for my $type ( keys %{ $prereqs->{$phase} } ) {
            for my $module ( keys %{ $prereqs->{$phase}{$type} } ) {
                $collector->{$phase}{$type}{$module} = $prereqs->{$phase}{$type}{$module};
            }
        }
    }

    return $collector;
}

my @include = qw(
  Encode
  File::Temp
  JSON::PP
  Module::Runtime
  Pod::Coverage
  Sub::Name
  YAML
  autodie
  Dist::CheckConflicts
);

my @exclude = qw(

);

# Add static prereqs to the included modules list
my $static_prereqs = do './t/00-report-prereqs.dd';

# Merge all prereqs (either with ::Prereqs or a hashref)
my $full_prereqs = _merge_prereqs(
    ( $HAS_CPAN_META ? $cpan_meta_pre->new : {} ),
    $static_prereqs
);

# Add dynamic prereqs to the included modules list (if we can)
my ($source) = grep { -f } 'MYMETA.json', 'MYMETA.yml';
my $cpan_meta_error;
if ( $source && $HAS_CPAN_META
    && (my $meta = eval { CPAN::Meta->load_file($source) } )
) {
    $full_prereqs = _merge_prereqs($full_prereqs, $meta->prereqs);
}
else {
    $cpan_meta_error = $@;    # capture error from CPAN::Meta->load_file($source)
    $source = 'static metadata';
}

my @full_reports;
my @dep_errors;
my $req_hash = $HAS_CPAN_META ? $full_prereqs->as_string_hash : $full_prereqs;

# Add static includes into a fake section
for my $mod (@include) {
    $req_hash->{other}{modules}{$mod} = 0;
}

for my $phase ( qw(configure build test runtime develop other) ) {
    next unless $req_hash->{$phase};
    next if ($phase eq 'develop' and not $ENV{AUTHOR_TESTING});

    for my $type ( qw(requires recommends suggests conflicts modules) ) {
        next unless $req_hash->{$phase}{$type};

        my $title = ucfirst($phase).' '.ucfirst($type);
        my @reports = [qw/Module Want Have/];

        for my $mod ( sort keys %{ $req_hash->{$phase}{$type} } ) {
            next if $mod eq 'perl';
            next if grep { $_ eq $mod } @exclude;

            my $file = $mod;
            $file =~ s{::}{/}g;
            $file .= ".pm";
            my ($prefix) = grep { -e File::Spec->catfile($_, $file) } @INC;

            my $want = $req_hash->{$phase}{$type}{$mod};
            $want = "undef" unless defined $want;
            $want = "any" if !$want && $want == 0;

            my $req_string = $want eq 'any' ? 'any version required' : "version '$want' required";

            if ($prefix) {
                my $have = Module::Metadata->new_from_file( File::Spec->catfile($prefix, $file) )->version;
                $have = "undef" unless defined $have;
                push @reports, [$mod, $want, $have];

                if ( $DO_VERIFY_PREREQS && $HAS_CPAN_META && $type eq 'requires' ) {
                    if ( $have !~ /\A$lax_version_re\z/ ) {
                        push @dep_errors, "$mod version '$have' cannot be parsed ($req_string)";
                    }
                    elsif ( ! $full_prereqs->requirements_for( $phase, $type )->accepts_module( $mod => $have ) ) {
                        push @dep_errors, "$mod version '$have' is not in required range '$want'";
                    }
                }
            }
            else {
                push @reports, [$mod, $want, "missing"];

                if ( $DO_VERIFY_PREREQS && $type eq 'requires' ) {
                    push @dep_errors, "$mod is not installed ($req_string)";
                }
            }
        }

        if ( @reports ) {
            push @full_reports, "=== $title ===\n\n";

            my $ml = _max( map { length $_->[0] } @reports );
            my $wl = _max( map { length $_->[1] } @reports );
            my $hl = _max( map { length $_->[2] } @reports );

            if ($type eq 'modules') {
                splice @reports, 1, 0, ["-" x $ml, "", "-" x $hl];
                push @full_reports, map { sprintf("    %*s %*s\n", -$ml, $_->[0], $hl, $_->[2]) } @reports;
            }
            else {
                splice @reports, 1, 0, ["-" x $ml, "-" x $wl, "-" x $hl];
                push @full_reports, map { sprintf("    %*s %*s %*s\n", -$ml, $_->[0], $wl, $_->[1], $hl, $_->[2]) } @reports;
            }

            push @full_reports, "\n";
        }
    }
}

if ( @full_reports ) {
    diag "\nVersions for all modules listed in $source (including optional ones):\n\n", @full_reports;
}

if ( $cpan_meta_error || @dep_errors ) {
    diag "\n*** WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING ***\n";
}

if ( $cpan_meta_error ) {
    my ($orig_source) = grep { -f } 'MYMETA.json', 'MYMETA.yml';
    diag "\nCPAN::Meta->load_file('$orig_source') failed with: $cpan_meta_error\n";
}

if ( @dep_errors ) {
    diag join("\n",
        "\nThe following REQUIRED prerequisites were not satisfied:\n",
        @dep_errors,
        "\n"
    );
}

pass;

# vim: ts=4 sts=4 sw=4 et:
