$TTL 604800
$ORIGIN homelab.kubernerdes.com.
@	IN SOA      nuc-00.homelab.kubernerdes.com.  root.kubernerdes.com. (
            2026071201 ; Serial
            604800     ; Refresh
            86400      ; Retry
            2419200    ; Expire
            604800 )   ; Negative Cache TTL

             IN NS       nuc-00.homelab.kubernerdes.com.

; Infra Hardware devices
sophos-xgs88 	IN 	A	10.10.12.1
firewall 	IN	CNAME	sophos-xgs88.homelab.kubernerdes.com.
gateway		IN	CNAME	sophos-xgs88.homelab.kubernerdes.com.
cisco-sg300-28	IN 	A	10.10.12.2
airport-extreme IN 	A	10.10.12.3
truenas		 IN 	A	10.10.12.7

; Infra Hosts
; NOTE: nuc-00-01 (DNS/DHCP/TFTP) and nuc-00-02 (DNS secondary) are retired —
; nuc-00 now runs all infra services directly. See PLAN.md.
nuc-00		IN	A	10.10.12.10
truenas		IN	A	10.10.12.11
glkvm		IN	A	10.10.12.20

; Load Balancer for Harvester Cluster(s) - one LB per K8s Cluster (sometimes paired)
; These are the Host Address - define VIP elsewhere
nuc-00-03	IN	A	10.10.12.93

blackmesa	IN	A	10.10.12.247
wall-e		IN 	A	10.10.12.248
wheatley	IN 	A	10.10.12.249
jarvis		IN 	A	10.10.12.250
*.jarvis		IN 	A	10.10.12.250
spark-e		IN 	A	10.10.12.251
los-alamos	IN 	A	10.10.12.252

docs            IN      CNAME   cloudxabide.github.io.

; DHCP Hosts
dhcp-128    IN      A       10.10.12.128
dhcp-129    IN      A       10.10.12.129
dhcp-130    IN      A       10.10.12.130
dhcp-131    IN      A       10.10.12.131
dhcp-132    IN      A       10.10.12.132
dhcp-133    IN      A       10.10.12.133
dhcp-134    IN      A       10.10.12.134
dhcp-135    IN      A       10.10.12.135
dhcp-136    IN      A       10.10.12.136
dhcp-137    IN      A       10.10.12.137
dhcp-138    IN      A       10.10.12.138
dhcp-139    IN      A       10.10.12.139
dhcp-140    IN      A       10.10.12.140
dhcp-141    IN      A       10.10.12.141
dhcp-142    IN      A       10.10.12.142
dhcp-143    IN      A       10.10.12.143
dhcp-144    IN      A       10.10.12.144
dhcp-145    IN      A       10.10.12.145
dhcp-146    IN      A       10.10.12.146
dhcp-147    IN      A       10.10.12.147
dhcp-148    IN      A       10.10.12.148
dhcp-149    IN      A       10.10.12.149
dhcp-150    IN      A       10.10.12.150
dhcp-151    IN      A       10.10.12.151
dhcp-152    IN      A       10.10.12.152
dhcp-153    IN      A       10.10.12.153
dhcp-154    IN      A       10.10.12.154
dhcp-155    IN      A       10.10.12.155
dhcp-156    IN      A       10.10.12.156
dhcp-157    IN      A       10.10.12.157
dhcp-158    IN      A       10.10.12.158
dhcp-159    IN      A       10.10.12.159
dhcp-160    IN      A       10.10.12.160
dhcp-161    IN      A       10.10.12.161
dhcp-162    IN      A       10.10.12.162
dhcp-163    IN      A       10.10.12.163
dhcp-164    IN      A       10.10.12.164
dhcp-165    IN      A       10.10.12.165
dhcp-166    IN      A       10.10.12.166
dhcp-167    IN      A       10.10.12.167
dhcp-168    IN      A       10.10.12.168
dhcp-169    IN      A       10.10.12.169
dhcp-170    IN      A       10.10.12.170
dhcp-171    IN      A       10.10.12.171
dhcp-172    IN      A       10.10.12.172
dhcp-173    IN      A       10.10.12.173
dhcp-174    IN      A       10.10.12.174
dhcp-175    IN      A       10.10.12.175
dhcp-176    IN      A       10.10.12.176
dhcp-177    IN      A       10.10.12.177
dhcp-178    IN      A       10.10.12.178
dhcp-179    IN      A       10.10.12.179
dhcp-180    IN      A       10.10.12.180
dhcp-181    IN      A       10.10.12.181
dhcp-182    IN      A       10.10.12.182
dhcp-183    IN      A       10.10.12.183
dhcp-184    IN      A       10.10.12.184
dhcp-185    IN      A       10.10.12.185
dhcp-186    IN      A       10.10.12.186
dhcp-187    IN      A       10.10.12.187
dhcp-188    IN      A       10.10.12.188
dhcp-189    IN      A       10.10.12.189
dhcp-190    IN      A       10.10.12.190
dhcp-191    IN      A       10.10.12.191
dhcp-192    IN      A       10.10.12.192
dhcp-193    IN      A       10.10.12.193
dhcp-194    IN      A       10.10.12.194
dhcp-195    IN      A       10.10.12.195
dhcp-196    IN      A       10.10.12.196
dhcp-197    IN      A       10.10.12.197
dhcp-198    IN      A       10.10.12.198
dhcp-199    IN      A       10.10.12.199
dhcp-200    IN      A       10.10.12.200
dhcp-201    IN      A       10.10.12.201
dhcp-202    IN      A       10.10.12.202
dhcp-203    IN      A       10.10.12.203
dhcp-204    IN      A       10.10.12.204
dhcp-205    IN      A       10.10.12.205
dhcp-206    IN      A       10.10.12.206
dhcp-207    IN      A       10.10.12.207
dhcp-208    IN      A       10.10.12.208
dhcp-209    IN      A       10.10.12.209
dhcp-210    IN      A       10.10.12.210
dhcp-211    IN      A       10.10.12.211
dhcp-212    IN      A       10.10.12.212
dhcp-213    IN      A       10.10.12.213
dhcp-214    IN      A       10.10.12.214
dhcp-215    IN      A       10.10.12.215
dhcp-216    IN      A       10.10.12.216
dhcp-217    IN      A       10.10.12.217
dhcp-218    IN      A       10.10.12.218
dhcp-219    IN      A       10.10.12.219
dhcp-220    IN      A       10.10.12.220
dhcp-221    IN      A       10.10.12.221
dhcp-222    IN      A       10.10.12.222
dhcp-223    IN      A       10.10.12.223
dhcp-224    IN      A       10.10.12.224
dhcp-225    IN      A       10.10.12.225
dhcp-226    IN      A       10.10.12.226
dhcp-227    IN      A       10.10.12.227
dhcp-228	 IN	 A	 10.10.12.228
dhcp-229	 IN	 A	 10.10.12.229
dhcp-230	 IN	 A	 10.10.12.230
dhcp-231	 IN	 A	 10.10.12.231
dhcp-232	 IN	 A	 10.10.12.232
dhcp-233	 IN	 A	 10.10.12.233
dhcp-234	 IN	 A	 10.10.12.234
dhcp-235	 IN	 A	 10.10.12.235
dhcp-236	 IN	 A	 10.10.12.236
dhcp-237	 IN	 A	 10.10.12.237
dhcp-238	 IN	 A	 10.10.12.238
dhcp-239	 IN	 A	 10.10.12.239
dhcp-240	 IN	 A	 10.10.12.240
dhcp-241	 IN	 A	 10.10.12.241
dhcp-242	 IN	 A	 10.10.12.242
dhcp-243	 IN	 A	 10.10.12.243
dhcp-244	 IN	 A	 10.10.12.244
