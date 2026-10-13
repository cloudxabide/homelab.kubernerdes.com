
I have an issue with the NIC flaking out and going offline while generating syslog entries about a hung device.

## Manually set the values (to test)
```
ethtool -K eno1 tso off gso off gro off
ethtool --set-eee eno1 eee off || true
```

## Update Harvester for persistent configuration
Applies to nodes where eno1 uses the e1000e driver (nuc-01/02/03 - check with `ethtool -i eno1`).
```
sudo tee /oem/99_nic_fix.yaml >/dev/null <<'EOF'
name: "e1000e offload workaround"
stages:
  network:
    - name: "disable offloads and EEE on e1000e NIC (eno1)"
      commands:
        - ethtool -K eno1 tso off gso off gro off
        - ethtool --set-eee eno1 eee off || true
EOF
sudo chmod 600 /oem/99_nic_fix.yaml
```

## Verify (after a reboot)
```
sudo ethtool -k eno1 | grep -E "^(tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload):"
sudo ethtool --show-eee eno1 | grep "EEE status"
sudo dmesg | grep -i "Hardware Unit Hang"
```
