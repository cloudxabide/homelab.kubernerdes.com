$TTL 604800 
$ORIGIN community.kubernerdes.com. 
@	IN SOA      nuc-00.homelab.kubernerdes.com.  root.kubernerdes.com. ( 
            2026071201 ; Serial
            604800     ; Refresh
            86400      ; Retry
            2419200    ; Expire
            604800 )   ; Negative Cache TTL

             IN NS       nuc-00.homelab.kubernerdes.com.

; NOTE: I no longer have static IPs for the VMs
; Rancher Cluster
rancher         IN      A       10.10.14.30

; Observability Cluster
observability   IN      A       10.10.14.40

; Apps Cluster
apps            IN      A       10.10.14.50

; Load Balancer for Harvester Cluster(s) - one LB per Harvester Cluster
; These are the Host Address - define VIP elsewhere
nuc-00-03	IN	A	10.10.14.93

; Hardware Devices in the 1xx range
; NUC cluster (Harvester Edge)
harvester	IN	A	10.10.14.100
nuc-01		IN	A	10.10.14.101
nuc-02		IN	A	10.10.14.102
nuc-03		IN	A	10.10.14.103

nuc-01-kvm	IN	A	10.10.14.111
nuc-02-kvm	IN	A	10.10.14.112
nuc-03-kvm	IN	A	10.10.14.113

; DHCP CIDR 10.10.14.0/24
dhcp-128    IN      A       10.10.14.128
dhcp-129    IN      A       10.10.14.129
dhcp-130    IN      A       10.10.14.130
dhcp-131    IN      A       10.10.14.131
dhcp-132    IN      A       10.10.14.132
dhcp-133    IN      A       10.10.14.133
dhcp-134    IN      A       10.10.14.134
dhcp-135    IN      A       10.10.14.135
dhcp-136    IN      A       10.10.14.136
dhcp-137    IN      A       10.10.14.137
dhcp-138    IN      A       10.10.14.138
dhcp-139    IN      A       10.10.14.139
dhcp-140    IN      A       10.10.14.140
dhcp-141    IN      A       10.10.14.141
dhcp-142    IN      A       10.10.14.142
dhcp-143    IN      A       10.10.14.143
dhcp-144    IN      A       10.10.14.144
dhcp-145    IN      A       10.10.14.145
dhcp-146    IN      A       10.10.14.146
dhcp-147    IN      A       10.10.14.147
dhcp-148    IN      A       10.10.14.148
dhcp-149    IN      A       10.10.14.149
dhcp-150    IN      A       10.10.14.150
dhcp-151    IN      A       10.10.14.151
dhcp-152    IN      A       10.10.14.152
dhcp-153    IN      A       10.10.14.153
dhcp-154    IN      A       10.10.14.154
dhcp-155    IN      A       10.10.14.155
dhcp-156    IN      A       10.10.14.156
dhcp-157    IN      A       10.10.14.157
dhcp-158    IN      A       10.10.14.158
dhcp-159    IN      A       10.10.14.159
dhcp-160    IN      A       10.10.14.160
dhcp-161    IN      A       10.10.14.161
dhcp-162    IN      A       10.10.14.162
dhcp-163    IN      A       10.10.14.163
dhcp-164    IN      A       10.10.14.164
dhcp-165    IN      A       10.10.14.165
dhcp-166    IN      A       10.10.14.166
dhcp-167    IN      A       10.10.14.167
dhcp-168    IN      A       10.10.14.168
dhcp-169    IN      A       10.10.14.169
dhcp-170    IN      A       10.10.14.170
dhcp-171    IN      A       10.10.14.171
dhcp-172    IN      A       10.10.14.172
dhcp-173    IN      A       10.10.14.173
dhcp-174    IN      A       10.10.14.174
dhcp-175    IN      A       10.10.14.175
dhcp-176    IN      A       10.10.14.176
dhcp-177    IN      A       10.10.14.177
dhcp-178    IN      A       10.10.14.178
dhcp-179    IN      A       10.10.14.179
dhcp-180    IN      A       10.10.14.180
dhcp-181    IN      A       10.10.14.181
dhcp-182    IN      A       10.10.14.182
dhcp-183    IN      A       10.10.14.183
dhcp-184    IN      A       10.10.14.184
dhcp-185    IN      A       10.10.14.185
dhcp-186    IN      A       10.10.14.186
dhcp-187    IN      A       10.10.14.187
dhcp-188    IN      A       10.10.14.188
dhcp-189    IN      A       10.10.14.189
dhcp-190    IN      A       10.10.14.190
dhcp-191    IN      A       10.10.14.191
dhcp-192    IN      A       10.10.14.192
dhcp-193    IN      A       10.10.14.193
dhcp-194    IN      A       10.10.14.194
dhcp-195    IN      A       10.10.14.195
dhcp-196    IN      A       10.10.14.196
dhcp-197    IN      A       10.10.14.197
dhcp-198    IN      A       10.10.14.198
dhcp-199    IN      A       10.10.14.199
dhcp-200    IN      A       10.10.14.200
dhcp-201    IN      A       10.10.14.201
dhcp-202    IN      A       10.10.14.202
dhcp-203    IN      A       10.10.14.203
dhcp-204    IN      A       10.10.14.204
dhcp-205    IN      A       10.10.14.205
dhcp-206    IN      A       10.10.14.206
dhcp-207    IN      A       10.10.14.207
dhcp-208    IN      A       10.10.14.208
dhcp-209    IN      A       10.10.14.209
dhcp-210    IN      A       10.10.14.210
dhcp-211    IN      A       10.10.14.211
dhcp-212    IN      A       10.10.14.212
dhcp-213    IN      A       10.10.14.213
dhcp-214    IN      A       10.10.14.214
dhcp-215    IN      A       10.10.14.215
dhcp-216    IN      A       10.10.14.216
dhcp-217    IN      A       10.10.14.217
dhcp-218    IN      A       10.10.14.218
dhcp-219    IN      A       10.10.14.219
dhcp-220    IN      A       10.10.14.220
dhcp-221    IN      A       10.10.14.221
dhcp-222    IN      A       10.10.14.222
dhcp-223    IN      A       10.10.14.223
dhcp-224    IN      A       10.10.14.224
dhcp-225    IN      A       10.10.14.225
dhcp-226    IN      A       10.10.14.226
dhcp-227    IN      A       10.10.14.227
dhcp-228	 IN	 A	 10.10.14.228
dhcp-229	 IN	 A	 10.10.14.229
dhcp-230	 IN	 A	 10.10.14.230
dhcp-231	 IN	 A	 10.10.14.231
dhcp-232	 IN	 A	 10.10.14.232
dhcp-233	 IN	 A	 10.10.14.233
dhcp-234	 IN	 A	 10.10.14.234
dhcp-235	 IN	 A	 10.10.14.235
dhcp-236	 IN	 A	 10.10.14.236
dhcp-237	 IN	 A	 10.10.14.237
dhcp-238	 IN	 A	 10.10.14.238
dhcp-239	 IN	 A	 10.10.14.239
dhcp-240	 IN	 A	 10.10.14.240
dhcp-241	 IN	 A	 10.10.14.241
dhcp-242	 IN	 A	 10.10.14.242
dhcp-243	 IN	 A	 10.10.14.243
dhcp-244	 IN	 A	 10.10.14.244
dhcp-245	 IN	 A	 10.10.14.245
dhcp-246	 IN	 A	 10.10.14.246
dhcp-247	 IN	 A	 10.10.14.247
dhcp-248	 IN	 A	 10.10.14.248
dhcp-249	 IN	 A	 10.10.14.249
dhcp-250	 IN	 A	 10.10.14.250
dhcp-251	 IN	 A	 10.10.14.251
dhcp-252	 IN	 A	 10.10.14.252
dhcp-253	 IN	 A	 10.10.14.253
dhcp-254	 IN	 A	 10.10.14.254

; Application Wildcard Endpoints
*.apps.community.kubernerdes.com. 	IN 	A 	10.10.14.51

; Docs hosted at github pages
docs.community.kubernerdes.com.   IN      CNAME   jradtke-rgs.github.io.

; Harbor CNAME
harbor.community.kubernerdes.com.	IN	CNAME nuc-00.community.kubernerdes.com.

