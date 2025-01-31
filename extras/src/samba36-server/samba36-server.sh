#!/bin/sh

if [ "$(basename $0)" = "tch-gui-unhide-xtra.samba36-server" -o -z "$FW_BASE" ]; then
  echo "ERROR: This script must NOT be executed!"
  echo "       Place it in the same directory as tch-gui-unhide and it will"
  echo "       be applied automatically when you run tch-gui-unhide."
  exit
fi

# The tch-gui-unhide-xtra scripts should output a single line to indicate success or failure
# as the calling script has left a hanging echo -n. Include a leading space for clarity.

which smbd >/dev/null
if [ $? -eq 0 -a -z "$XTRAS_REMOVE" ]; then
  smbd -V | grep -q '^Version 3\.6\.'
  if [ $? -eq 0 ]; then
    conf="/etc/samba/smb.conf.template"
    echo -n " Adding SMBv2 support."
    /etc/init.d/samba stop
    /etc/init.d/samba-nmbd stop
    /etc/init.d/samba-nmbd disable

    for p in $(ps | grep -E '/usr/sbin/.mbd' | grep -v grep | cut -c1-5); do
      kill $p
    done

    grep -q "^samba:" /etc/group || echo "samba:x:1000:" >> /etc/group
    grep -q "^samba:" /etc/passwd || echo "samba:x:1000:1000:samba:/var:/bin/false" >> /etc/passwd
    grep -q "^samba:" /etc/samba/smbpasswd
    if [ $? -eq 1 ]; then
      echo -e "\n\n" | smbpasswd -s -a samba
      echo " NOTE: Username is samba with NO password. You can change the password in the GUI."
    else
      echo
    fi

    sed -e 's/"name" }/"name", "users" }/' -i /usr/share/transformer/mappings/uci/samba.map
    if [ ! -f /usr/share/transformer/mappings/rpc/gui.samba.map ]; then
      cat <<MAP > /usr/share/transformer/mappings/rpc/gui.samba.map
MAP
      chmod 644 /usr/share/transformer/mappings/rpc/gui.samba.map
    fi
    SRV_transformer=$(( $SRV_transformer + 2 ))

    sed -e 's/security = share/security = user/' -i $conf
    grep -q "$(echo -e '\tmin protocol')" $conf        || echo -e '\tmin protocol = SMB2' >> $conf
    grep -q "$(echo -e '\tmax protocol')" $conf        || echo -e '\tmax protocol = SMB2' >> $conf
    grep -q "$(echo -e '\tserver min protocol')" $conf || echo -e '\tserver min protocol = SMB2' >> $conf
    grep -q "$(echo -e '\tclient min protocol')" $conf || echo -e '\tclient min protocol = SMB2' >> $conf
    grep -q "$(echo -e '\tclient max protocol')" $conf || echo -e '\tclient max protocol = SMB2' >> $conf
    grep -q "$(echo -e '\tnull passwords')" $conf      || echo -e '\tnull passwords = yes' >> $conf

    sed \
      -e 's/guest ok = yes/guest ok = no/' \
      -e 's/guest_ok=yes/guest_ok=no/' \
      -i /lib/functions/contentsharing.sh
    grep -q "users = samba" /lib/functions/contentsharing.sh || sed -e '/guest ok =/a \       users = samba' -i /lib/functions/contentsharing.sh
    grep -q "\.users=samba" /lib/functions/contentsharing.sh || sed -e '/guest_ok=/a \  uci -P /var/state set samba.\${sharename}.users=samba' -i /lib/functions/contentsharing.sh

    usb=$(ls /var/etc/smb.auto/USB-*.conf 2>/dev/null)
    if [ ! -z "$usb" ]; then
      for f in $usb; do
        sharename=$(head -n 1 $f | tr -d '[]')
        sed -e 's/guest ok = yes/guest ok = no/' -i $f
        grep -q "users = samba" $f || sed -e '/guest ok =/a \       users = samba' -i $f
        uci -q -P /var/state set samba.${sharename}.users=samba
        uci -q -P /var/state set samba.${sharename}.guest_ok=no
        uci -q -P /var/state commit samba
      done
    fi

    grep -q sambaconfigsdir /etc/init.d/samba || sed \
      -e "/config_foreach smb_add_share sambashare/a \ $(echo -e '\t')local sambaconfigsdir=\"\$(uci -P /var/state get samba.samba.configsdir | sed 's:/*\$::')\"" \
      -e "/config_foreach smb_add_share sambashare/a \ $(echo -e '\t')for f in \$(find \$sambaconfigsdir -type f); do" \
      -e "/config_foreach smb_add_share sambashare/a \ $(echo -e '\t\t')echo include = \$f >> /var/etc/smb.conf" \
      -e "/config_foreach smb_add_share sambashare/a \ $(echo -e '\t')done" \
      -i /etc/init.d/samba

    uci set samba.samba.homes='0'
    uci commit samba

    /etc/init.d/samba start

    sed \
      -e '/^    post_data = ngx.req.get_post_args()/a \    if post_data["samba_password"] ~= "********" then' \
      -e '/^    post_data = ngx.req.get_post_args()/a \        if proxy.set("rpc.gui.samba.passwd", post_data["samba_password"]) then' \
      -e '/^    post_data = ngx.req.get_post_args()/a \            proxy.apply()' \
      -e '/^    post_data = ngx.req.get_post_args()/a \            message_helper.pushMessage(T"Password changed.", "success")' \
      -e '/^    post_data = ngx.req.get_post_args()/a \        end' \
      -e '/^    post_data = ngx.req.get_post_args()/a \    end' \
      -e '/ui_helper.createInputText(T"File Server description:/a \                tinsert(html, ui_helper.createLabel(T"Share Username", "samba", advanced))' \
      -e '/ui_helper.createInputText(T"File Server description:/a \                tinsert(html, ui_helper.createInputPassword(T"Share Password", "samba_password", "********", advanced))' \
      -i /www/docroot/modals/contentsharing-modal.lp
  else
    grep -q "^samba:" /etc/samba/smbpasswd
    if [ $? -eq 0 ]; then
      echo " samba36-server removed - Restoring default samba installation"
      /etc/init.d/samba stop

      for p in $(ps | grep -E '/usr/sbin/.mbd' | grep -v grep | cut -c1-5); do
        kill $p
      done

      sed -e '/^samba/d' -i /etc/passwd
      sed -e '/^samba/d' -i /etc/group
      grep -q "^samba:" /etc/samba/smbpasswd || smbpasswd -x samba

      for f in /usr/share/transformer/mappings/uci/samba.map \
              $(cat /usr/lib/opkg/info/samba-tch*.list) \
              /etc/config/samba \
              /etc/init.d/samba \
              /etc/samba/* \
              /usr/sbin/nmbd \
              /usr/sbin/smbd \
              /usr/sbin/smbpasswd
      do
        if [ -f /rom$f ]; then
          if [ ! -f $f ]; then
            cp -p /rom$f $f
          else
            cmp -s /rom$f $f
            if [ $? -eq 1 ]; then
              cp -p /rom$f $f
            fi
          fi
        fi
      done

      SRV_transformer=$(( $SRV_transformer + 1 ))

      sed \
        -e '/users = samba/d' \
        -e '/uci -P /var/state set samba.\${sharename}.users=samba/d' \
        -e 's/guest ok = no/guest ok = yes/' \
        -e 's/guest_ok=no/guest_ok=yes/' \
        -i /lib/functions/contentsharing.sh

      for f in /var/etc/smb.auto/USB-*.conf; do
        sharename=$(head -n 1 $f | tr -d '[]')
        sed -e 's/guest ok = no/guest ok = yes/' -i $f
        grep -q "users = samba" $f && sed -e '/users = samba/d' -i $f
        uci -q -P /var/state delete samba.${sharename}.users
        uci -q -P /var/state set samba.${sharename}.guest_ok=yes
        uci -q -P /var/state commit samba
      done

      uci set samba.samba.homes='1'
      uci commit samba

      /etc/init.d/samba start
      /etc/init.d/samba-nmbd enable
      /etc/init.d/samba-nmbd start
    else
      echo " SKIPPED because samba36-server not installed"
    fi
  fi
else
  echo " SKIPPED because samba36-server not installed"
fi