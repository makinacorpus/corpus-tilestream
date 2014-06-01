{% import "makina-states/localsettings/nodejs/prefix/prerequisites.sls" as node with context %}
{% import "makina-states/services/monitoring/supervisor/macros.jinja" as supervisor with context %}
{% import "makina-states/services/http/nginx/init.sls" as nginx %}
{% set msalt = salt['mc_salt.settings']() %}
{% set data = opts['ms_project'] %}
{% set odata = data.data %}
{% set sdata = salt['mc_utils.json_dump'](odata) %}
{% set supervisor_datas = [] %}
{% set shosts = {'a': ''}%}
{% for host in odata.tile_hosts %}
{%  do shosts.update({'a': '{1} --host "{0}"'.format(host, shosts['a'])}) %}
{% endfor %}

include:
  - makina-states.localsettings.nodejs
  - makina-states.services.http.nginx
  - makina-states.services.monitoring.supervisor

{{ node.install(odata.node_ver, hash=odata.node_hash) }}

{% for worker in range(odata.workers) %}
{%  do supervisor_datas.append({
      'process_name': '{0}.{1}'.format(data.name, loop.index0),
      'user': data.user,
      'directory': odata.troot,
    })%}
{% endfor %}

{% for supervisor_data in supervisor_datas %}
{% set launcher = "{0}/launcher{1}.sh".format(data.project_root, loop.index0) %}
{% do supervisor_data.update({'command': launcher}) %}
{{data.name}}-supervisor-exe{{loop.index0}}:
  file.managed:
    - name: {{launcher}}
    - mode: 750
    - template: jinja
    - user: {{data.user}}
    - group: {{data.group}}
    - watch_in:
      - mc_proxy: nginx-pre-restart-hook
      - mc_proxy: supervisor-pre-restart
    - contents: |
                #!/usr/bin/env bash
                cd {{odata.troot}}
                exec {{ ('{0} index.js'
                      ' --uiPort "{2}" --tilePort "{1}"'
                      ' --tiles "{3}" {4}'
                    ).format(
                      odata.node,
                      odata.ui_port + loop.index0,
                      odata.tile_port + loop.index0,
                      odata.tiles,
                      shosts.a,
                    ).replace('  ', ' ')}}
{{  supervisor.supervisorAddProgram(
  "{0}-{1}".format(data.name, loop.index0),
  **supervisor_data) }}
{% endfor %}

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
      - mc_proxy: supervisor-pre-restart
