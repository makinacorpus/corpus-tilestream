{% import "makina-states/localsettings/nodejs/prefix/prerequisites.sls" as node with context %}
{% import "makina-states/services/monitoring/circus/macros.jinja" as circus  with context %}
{% set cfg = opts['ms_project'] %}
{% set data = cfg.data %}
{% set scfg = salt['mc_utils.json_dump'](cfg) %}

include:
  - makina-states.localsettings.nodejs
  - makina-states.services.monitoring.circus

prepreqs-{{cfg.name}}:
  pkg.installed:
    - names:
      - sqlite3
      - libsqlite3-dev
      - apache2-utils

{{cfg.name}}-pull:
  git.latest:
    - user: {{cfg.user}}
    - name: {{data.turl}}
    - target: {{data.troot}}
    - watch:
      - pkg: prepreqs-{{cfg.name}}

{{cfg.name}}-dirs:
  file.directory:
    - watch:
      - pkg: prepreqs-{{cfg.name}}
      - git: {{cfg.name}}-pull
    - mode: 751
    - makedirs: true
    - names:
      - {{data.tiles}}
      - {{data.docroot}}
    - user: {{cfg.user}}
    - group: {{cfg.group}}

{{ node.install(data.node_ver, hash=data.node_hash) }}

npminstall-{{cfg.name}}:
  cmd.run:
    - name: {{data.node}} {{data.npm}} install
    - cwd: {{data.troot}}
    - user: {{cfg.user}}
    - watch:
      - file: {{cfg.name}}-dirs
    - watch_in:
      - mc_proxy: circus-pre-restart
npminstall-{{cfg.name}}-patch:
  cmd.run:
    - name: |
            sed -i -re  "s/(\s+if.* throw err;)/\/\/\1/g" node_modules/bones/server/plugin.js
    - cwd: {{data.troot}}
    - user: {{cfg.user}}
    - watch:
      - file: {{cfg.name}}-dirs
      - cmd: npminstall-{{cfg.name}}
    - watch_in:
      - mc_proxy: circus-pre-restart

{% for i in data.server_aliases %}
{%  if i not in data.tile_hosts%}
{%    do data.tile_hosts.append(i) %}
{%  endif %}
{% endfor %}

{% for worker in range(data.workers) %}
{% set circus_data = {
     'cmd':  (
     '{0} index.js --uiPort {1} --tilePort {2} --tiles {3} --host "{4}"'.format(
           data.node,
           data.ui_port+loop.index0,
           data.tile_port+loop.index0,
           data.tiles,
           '" --host "'.join(data.tile_hosts))),
      'uid': cfg.user,
      'gid': cfg.group,
      'copy_env': True,
      'working_dir': data.troot,
      'warmup_delay': "10",
      'max_age': 24*60*60} %}
{{ circus.circusAddWatcher("{0}-{1}".format(cfg.name, loop.index0), **circus_data) }}
{% endfor %}
