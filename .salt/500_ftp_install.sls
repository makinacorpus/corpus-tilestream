{% set cfg = opts.ms_project %}
include:
  - makina-states.services.ftp.pureftpd
{% set apacheSettings = salt['mc_apache.settings']() %}
{% set data = cfg.data %}

{{cfg.name}}-bindmounted-ftp:
  file.directory:
    - names:
      - {{cfg.data.ftp_root}}
    - user: {{apacheSettings.httpd_user}}
    - group: {{apacheSettings.httpd_user}}
    - mode:  775
    - makedirs: true

{# create each user, his home and base layout #}
{% for userdef in cfg.data.get('users', []) %}
{% for user, udata in userdef.items() %}

{% set uhome = udata.get('home', cfg.data.ftp_root) %}
{{cfg.name}}-ftp-user-{{user}}:
  group.present:
    - name: {{user}}
  user.present:
    - shell: /bin/ftponly
    - name: {{user}}
    - password: {{salt['mc_utils.unix_crypt'](udata.password)}}
    - group: {{user}}
    - fullname: {{user}} user
    - optional_groups: []
    - home: {{uhome}}
    - remove_groups: False
    - gid_from_name: True
    - watch:
      - group: {{cfg.name}}-ftp-user-{{user}}

{{cfg.name}}-{{salt['mc_apache.settings']().httpd_user}}-in-ftpgroup-{{user}}:
  user.present:
    - name: {{apacheSettings.httpd_user}}
    - remove_groups: False
    - groups:
      - {{user}}
    - watch:
      - user: {{cfg.name}}-ftp-user-{{user}}
{% endfor %}
{% endfor %}

{% if data.get('ftp_port_range', '') %}
/etc/pure-ftpd/conf/PassivePortRange:
  file.managed:
    - makedirs: true
    - contents: {{data.ftp_port_range}}
    - watch_in:
      - mc_proxy: ftpd-post-configuration-hook
{%endif%}
{% if data.get('ftp_ip', '') %}
/etc/pure-ftpd/conf/ForcePassiveIP:
  file.managed:
    - makedirs: true
    - contents: {{data.ftp_ip}}
    - watch_in:
      - mc_proxy: ftpd-post-configuration-hook
{% endif %}
