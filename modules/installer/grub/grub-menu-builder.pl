use strict;
use warnings;
use XML::LibXML;
use File::Basename;
use File::Path;
use File::stat;
use File::Copy;
use IO::File;
use POSIX;
use Cwd;

my $defaultConfig = $ARGV[1] or die;

my $dom = XML::LibXML->load_xml(location => $ARGV[0]);

sub get { my ($name) = @_; return $dom->findvalue("/expr/attrs/attr[\@name = '$name']/*/\@value"); }

my $grub = get("grub");
my $grubVersion = int(get("version"));
my $extraConfig = get("extraConfig");
my $extraPerEntryConfig = get("extraPerEntryConfig");
my $extraEntries = get("extraEntries");
my $extraEntriesBeforeNixOS = get("extraEntriesBeforeNixOS") eq "true";
my $splashImage = get("splashImage");
my $configurationLimit = int(get("configurationLimit"));
my $copyKernels = get("copyKernels") eq "true";
my $timeout = int(get("timeout"));
my $defaultEntry = int(get("default"));

die "unsupported GRUB version\n" if $grubVersion != 1 && $grubVersion != 2;

print STDERR "updating GRUB $grubVersion menu...\n";

mkpath("/boot/grub", 0, 0700);


# Discover whether /boot is on the same filesystem as / and
# /nix/store.  If not, then all kernels and initrds must be copied to
# /boot, and all paths in the GRUB config file must be relative to the
# root of the /boot filesystem.  `$bootRoot' is the path to be
# prepended to paths under /boot.
my $bootRoot = "/boot";
if (stat("/")->dev != stat("/boot")->dev) {
    $bootRoot = "";
    $copyKernels = 1;
} elsif (stat("/boot")->dev != stat("/nix/store")->dev) {
    $copyKernels = 1;
}


# Generate the header.
my $conf .= "# Automatically generated.  DO NOT EDIT THIS FILE!\n";

if ($grubVersion == 1) {
    $conf .= "
        default $defaultEntry
        timeout $timeout
    ";
    if ($splashImage) {
        copy $splashImage, "/boot/background.xpm.gz" or die "cannot copy $splashImage to /boot\n";
        $conf .= "splashimage $bootRoot/background.xpm.gz\n";
    }
}

else {
    copy "$grub/share/grub/unicode.pf2", "/boot/grub/unicode.pf2" or die "cannot copy unicode.pf2 to /boot/grub: $!\n";
    
    $conf .= "
        if [ -s \$prefix/grubenv ]; then
          load_env
        fi

        # ‘grub-reboot’ sets a one-time saved entry, which we process here and
        # then delete.
        if [ \"\${saved_entry}\" ]; then
          # The next line *has* to look exactly like this, otherwise KDM's
          # reboot feature won't work properly with GRUB 2.
          set default=\"\${saved_entry}\"
          set saved_entry=
          set prev_saved_entry=
          save_env saved_entry
          save_env prev_saved_entry
          set timeout=1
        else
          set default=$defaultEntry
          set timeout=$timeout
        fi

        if loadfont $bootRoot/grub/unicode.pf2; then
          set gfxmode=640x480
          insmod gfxterm
          insmod vbe
          terminal_output gfxterm
        fi
    ";

    if ($splashImage) {
	# FIXME: GRUB 1.97 doesn't resize the background image if it
        # doesn't match the video resolution.
        copy $splashImage, "/boot/background.png" or die "cannot copy $splashImage to /boot\n";
        $conf .= "
            insmod png
            if background_image $bootRoot/background.png; then
              set color_normal=white/black
              set color_highlight=black/white
            else
              set menu_color_normal=cyan/blue
              set menu_color_highlight=white/blue
            fi
        ";
    }
}

$conf .= "$extraConfig\n";


# Generate the menu entries.
my $curEntry = 0;
$conf .= "\n";

my %copied;
mkpath("/boot/kernels", 0, 0755) if $copyKernels;

sub copyToKernelsDir {
    my ($path) = @_;
    return $path unless $copyKernels;
    $path =~ /\/nix\/store\/(.*)/ or die;
    my $name = $1; $name =~ s/\//-/g;
    my $dst = "/boot/kernels/$name";
    # Don't copy the file if $dst already exists.  This means that we
    # have to create $dst atomically to prevent partially copied
    # kernels or initrd if this script is ever interrupted.
    if (! -e $dst) {
        my $tmp = "$dst.tmp";
        copy $path, $tmp or die "cannot copy $path to $tmp\n";
        rename $tmp, $dst or die "cannot rename $tmp to $dst\n";
    }
    $copied{$dst} = 1;
    return "$bootRoot/kernels/$name";
}

sub addEntry {
    my ($name, $path) = @_;
    return if $curEntry++ > $configurationLimit;
    return unless -e "$path/kernel" && -e "$path/initrd";

    my $kernel = copyToKernelsDir(Cwd::abs_path("$path/kernel"));
    my $initrd = copyToKernelsDir(Cwd::abs_path("$path/initrd"));
    my $xen = -e "$path/xen.gz" ? copyToKernelsDir(Cwd::abs_path("$path/xen")) : undef;

    # FIXME: $confName

    my $kernelParams =
        "systemConfig=" . Cwd::abs_path($path) . " " .
        "init=" . Cwd::abs_path("$path/init") . " " .
        join " ", IO::File->new("$path/kernel-params")->getlines;
    my $xenParams = $xen && -e "$path/xen-params" ? join " ", IO::File->new("$path/xen-params")->getlines : "";

    if ($grubVersion == 1) {
        $conf .= "title $name\n";
        $conf .= "  $extraPerEntryConfig\n" if $extraPerEntryConfig;
        $conf .= "  kernel $xen $xenParams\n" if $xen;
        $conf .= "  " . ($xen ? "module" : "kernel") . " $kernel $kernelParams\n";
        $conf .= "  " . ($xen ? "module" : "initrd") . " $initrd\n\n";
    } else {
        $conf .= "menuentry \"$name\" {\n";
        $conf .= "  $extraPerEntryConfig\n" if $extraPerEntryConfig;
        $conf .= "  multiboot $xen $xenParams\n" if $xen;
        $conf .= "  " . ($xen ? "module" : "linux") . " $kernel $kernelParams\n";
        $conf .= "  " . ($xen ? "module" : "initrd") . " $initrd\n";
        $conf .= "}\n\n";
    }
}


# Add default entries.
$conf .= "$extraEntries\n" if $extraEntriesBeforeNixOS;

addEntry("NixOS - Default", $defaultConfig);

$conf .= "$extraEntries\n" unless $extraEntriesBeforeNixOS;


# Add entries for all previous generations of the system profile.
$conf .= "submenu \"NixOS - Old configurations\" {\n" if $grubVersion == 2;

sub nrFromGen { my ($x) = @_; $x =~ /system-(.*)-link/; return $1; }
    
my @links = sort
    { nrFromGen($b) <=> nrFromGen($a) }
    (glob "/nix/var/nix/profiles/system-*-link");
    
foreach my $link (@links) {
    my $date = strftime("%F", localtime(lstat($link)->mtime));
    my $version =
        -e "$link/nixos-version"
        ? IO::File->new("$link/nixos-version")->getline
        : basename((glob(dirname(Cwd::abs_path("$link/kernel")) . "/lib/modules/*"))[0]);
    addEntry("NixOS - Configuration " . nrFromGen($link) . " ($date - $version)", $link);
}

$conf .= "}\n" if $grubVersion == 2;


# Atomically update the GRUB config.
my $confFile = $grubVersion == 1 ? "/boot/grub/menu.lst" : "/boot/grub/grub.cfg";
my $tmpFile = $confFile . ".tmp";
open CONF, ">$tmpFile" or die "cannot open $tmpFile for writing\n";
print CONF $conf or die;
close CONF;
rename $tmpFile, $confFile or die "cannot rename $tmpFile to $confFile\n";


# Remove obsolete files from /boot/kernels.
foreach my $fn (glob "/boot/kernels/*") {
    next if defined $copied{$fn};
    print STDERR "removing obsolete file $fn\n";
    unlink $fn;
}
