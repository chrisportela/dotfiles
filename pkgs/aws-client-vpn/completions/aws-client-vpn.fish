# aws-client-vpn(1) fish completion — candidates come from
# `aws-client-vpn __complete`.

# No bare file completion; the flags that take a path opt back in with -F.
complete -c aws-client-vpn -f

complete -c aws-client-vpn -s c -l config -r -F -a '(aws-client-vpn __complete configs)' \
  -d 'OpenVPN profile exported from the endpoint'
complete -c aws-client-vpn -s e -l endpoint -x -a '(aws-client-vpn __complete endpoints)' \
  -d 'Client VPN endpoint id to export a profile from'
complete -c aws-client-vpn -s p -l profile -x -a '(aws-client-vpn __complete profiles)' \
  -d 'AWS CLI profile used for the export'
complete -c aws-client-vpn -s r -l region -x -a '(aws-client-vpn __complete regions)' \
  -d 'AWS region used for the export'
complete -c aws-client-vpn -l port -x -d 'loopback port the assertion is posted back to'
complete -c aws-client-vpn -l timeout -x -d 'seconds to wait for the browser login'
complete -c aws-client-vpn -l dns -x -a 'auto systemd-resolved none' \
  -d 'how pushed DNS servers are applied'
complete -c aws-client-vpn -l no-browser -d 'print the login URL instead of opening a browser'
complete -c aws-client-vpn -s h -l help -d 'show help'
