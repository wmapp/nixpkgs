{stdenv, fetchurl, pkgconfig, glib, gtk, dbus, dbus_glib, GConf}:

stdenv.mkDerivation rec {
  name = "gnome-mplayer-1.0.4";

  src = fetchurl {
    url = "http://gnome-mplayer.googlecode.com/files/${name}.tar.gz";
    sha256 = "1k5yplsvddcm7xza5h4nfb6vibzjcqsk8gzis890alizk07f5xp2";
  };

  buildInputs = [pkgconfig glib gtk dbus dbus_glib GConf];
  
  meta = {
    homepage = http://kdekorte.googlepages.com/gnomemplayer;
    description = "Gnome MPlayer, a simple GUI for MPlayer";
  };
}
