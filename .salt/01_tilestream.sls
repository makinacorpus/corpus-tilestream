{% import "makina-states/localsettings/nodejs/prefix/prerequisites.sls" as node with context %}
{% import "makina-states/services/monitoring/circus/macros.jinja" as circus  with context %}
{% import "makina-states/services/http/nginx/init.sls" as nginx %}
{% set cfg = opts['ms_project'] %}
{% set data = cfg.data %}
{% set scfg = salt['mc_utils.json_dump'](cfg) %}

include:
  - makina-states.localsettings.nodejs
  - makina-states.services.http.nginx
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
    - pkg: prepreqs-{{cfg.name}}
    - watch:
      - git: {{cfg.name}}-pull
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
      - mc_proxy: nginx-pre-restart-hook
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

{{ nginx.virtualhost(domain=data.ui_domain,
                     active=True,
                     doc_root=data.docroot,
                     cfg=cfg,
                     vh_top_source=data.nginx_ui_upstreams,
                     vh_content_source=data.ui_vhost) }}
{{ nginx.virtualhost(domain=data.domain,
                     active=True,
                     doc_root=data.docroot,
                     cfg=cfg,
                     server_aliases=data.server_aliases,
                     redirect_aliases=False,
                     vh_top_source=data.nginx_upstreams,
                     vh_content_source=data.vhost) }}
