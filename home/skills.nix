{ pkgs, lib, inputs, ... }: let
  # Every agent we care about looks for skills in `<home>/.<tool>/skills/<dir>/SKILL.md`.
  # Each skill in `skills` below is symlinked into every directory listed here.
  agentSkillDirs = [
    ".claude/skills"
    ".codex/skills"
  ];

  # Fetch a skill tarball published to the npm registry. Pin with a sha256 so
  # the lockfile reproduces builds:
  #   { name = "my-skill";
  #     src = skillFromNpm { pname = "@scope/pkg"; version = "1.2.3"; hash = "sha256-..."; }; }
  # Compute the hash with:
  #   nix-prefetch-url --unpack https://registry.npmjs.org/<pname>/-/<basename>-<version>.tgz
  skillFromNpm = { pname, version, hash, subpath ? null }: let
    basename = lib.last (lib.splitString "/" pname);
    tarball = pkgs.fetchzip {
      url = "https://registry.npmjs.org/${pname}/-/${basename}-${version}.tgz";
      inherit hash;
    };
  in if subpath == null then tarball else "${tarball}/${subpath}";

  # Skill list. Each entry installs into every directory in `agentSkillDirs`
  # unless it sets `dirs`.
  #
  #   { name = "<directory-name>";
  #     src = <flake input or derivation containing SKILL.md>;
  #     subpath = <optional subdir within src>;
  #     dirs = <optional subset of agentSkillDirs>; }
  #
  # GitHub-sourced skills: declare them as `flake = false` inputs in flake.nix
  # and pass `inputs.<name>` as `src`. Run `nix flake update <name>` to bump.
  #
  # npm-sourced skills: use `skillFromNpm` above.
  skills = [
    {
      name = "receiving-code-review";
      src = inputs.superpowers;
      subpath = "skills/receiving-code-review";
    }
    # Same SKILL.md as Claude's frontend-design plugin, so don't also enable
    # that plugin or Claude lists the skill twice.
    {
      name = "frontend-design";
      src = inputs.anthropic-skills;
      subpath = "skills/frontend-design";
    }
  ]
  # Codex counterparts to the docx/pdf/pptx/xlsx skills Claude gets from the
  # claude.ai skill sync. Anthropic's versions may only be used within
  # Anthropic's services, so Codex gets OpenAI's Apache-2.0 ones.
  ++ map (name: {
    inherit name;
    src = inputs.openai-doc-skills;
    subpath = "skills/.curated/${name}";
    dirs = [ ".codex/skills" ];
  }) [ "doc" "pdf" "spreadsheet" "slides" ];

  resolveSrc = skill:
    if skill ? subpath && skill.subpath != null
    then "${skill.src}/${skill.subpath}"
    else "${skill.src}";

  skillFiles = lib.listToAttrs (lib.concatMap (skill:
    map (dir: lib.nameValuePair "${dir}/${skill.name}" {
      source = resolveSrc skill;
    }) (skill.dirs or agentSkillDirs)
  ) skills);
in {
  home.file = skillFiles;
}
