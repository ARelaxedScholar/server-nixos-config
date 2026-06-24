{ pkgs ? import <nixpkgs> {} }:

let
  python = pkgs.python3;

  scripts = [
    "swagwatch_lead_source_v7"
    "swagwatch_find_emails_v5"
    "swagwatch_gen_emails"
    "swagwatch_gen_msgs_v3"
    "swagwatch_gen_report"
  ];

  swagwatchScriptBin = name: pkgs.runCommand "swagwatch-${name}" {} ''
    mkdir -p $out/bin
    cp /home/user/${name}.py $out/bin/${name}.py
    sed -i "1s|.*|#!${python}/bin/python3|" $out/bin/${name}.py
    chmod +x $out/bin/${name}.py
    ${pkgs.makeWrapper}/bin/makeWrapper $out/bin/${name}.py $out/bin/${name} --set HOME /home/user --prefix PATH : ${python}/bin
  '';

in pkgs.buildEnv {
  name = "swagwatch-pipeline";
  paths = map swagwatchScriptBin scripts;
}
