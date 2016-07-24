{stdenv, fetchgit, libX11, libXrandr}:
stdenv.mkDerivation rec {
  name = "sct";
  buildInputs = [libX11 libXrandr];
  src = fetchgit {
    url = git://github.com/wmapp/sct.git;
    rev = "be00d189f491b9100233b3a623b026bbffccb18e";
    sha256 = "1fd2hdc1fklzspd9x2lm1hznlvqssiha8ckcr1zgmzq04rkwbl5r";
  };
  phases = ["patchPhase" "buildPhase" "installPhase"];
  patchPhase = ''
    sed -re "/Xlibint/d" ${src}/sct.c > sct.c 
  '';
  buildPhase = "gcc -std=c99 sct.c -o sct -lX11 -lXrandr -lm";
  installPhase = ''
    mkdir -p "$out/bin"
    cp sct "$out/bin"
  '';
  meta = {
    description = ''A minimal utility to set display colour temperature'';
    maintainers = [stdenv.lib.maintainers.raskin];
    platforms = with stdenv.lib.platforms; linux ++ freebsd ++ openbsd;
    homepage = http://www.tedunangst.com/flak/post/sct-set-color-temperature;
  };
}
