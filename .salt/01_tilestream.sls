{%- import "makina-states/services/monitoring/circus/macros.jinja" as circus with context %}
{% import "makina-states/services/http/nginx/init.sls" as nginx %}
{% set msalt = salt['mc_salt.settings']() %}
{% set data = opts['ms_project'] %}
{% set odata = data.data %}
{% set sdata = salt['mc_utils.json_dump'](odata) %}
{% set circus_datas = [] %}
{% for worker in range(odata.workers) %}
{%  do circus_datas.append({
      'uid': data.user,
      'gid': data.group,
      'working_dir': odata.troot,
      'cmd': odata.node,
      'args': (
            'index.js '
            ' --subdomains={4},{5}'
            ' --accesslog=1'
            ' --host={0}'
            ' --uiPort={2} --tilePort={1}'
            ' --tiles={3}'
      ).format(
        odata.node_host,
        odata.ui_port + loop.index0,
        odata.tile_port + loop.index0,
        odata.tiles,
        odata.ui_domain,
        odata.domain,
      ),
    })%}
{% endfor %}

include:
  - makina-states.localsettings.nodejs
  - makina-states.services.http.nginx
  - makina-states.services.monitoring.circus

{{ nginx.virtualhost(domain=odata.ui_domain,
                     active=True,
                     doc_root=odata.docroot,
                     extra=data,
                     vh_top_source=odata.nginx_ui_upstreams,
                     vh_content_source=odata.ui_vhost) }}
{{ nginx.virtualhost(domain=odata.domain,
                     active=True,
                     doc_root=odata.docroot,
                     extra=data,
                     vh_top_source=odata.nginx_upstreams,
                     vh_content_source=odata.vhost) }}

prepreqs-{{data.name}}:
  pkg.installed:
    - names:
      - sqlite3
      - libsqlite3-dev
      - apache2-utils

{{data.name}}-pull:
  git.latest:
    - user: {{data.user}}
    - name: {{odata.turl}}
    - target: {{odata.troot}}
    - watch:
      - pkg: prepreqs-{{data.name}}

{{data.name}}-dirs:
  file.directory:
    - pkg: prepreqs-{{data.name}}
    - watch:
      - git: {{data.name}}-pull
    - names:
      - {{odata.tiles}}
      - {{odata.docroot}}
    - user: {{data.user}}
    - group: {{data.group}}

npminstall-{{data.name}}:
  cmd.run:
    - name: {{odata.node}} {{odata.npm}} install
    - cwd: {{odata.troot}}
    - user: {{data.user}}
    - watch:
      - file: {{data.name}}-dirs
    - watch_in:
      - mc_proxy: nginx-pre-restart-hook
      - mc_proxy: circus-pre-restart

{% for circus_data in circus_datas %}
{{  circus.circusAddWatcher(
  "{0}-{1}".format(data.name, loop.index0),
  **circus_data) }}
{% endfor %}

