$TTL 604800 
$ORIGIN enclave.kubernerdes.com. 
@	IN SOA      nuc-00.homelab.kubernerdes.com.  root.kubernerdes.com. ( 
            2026071201 ; Serial
            604800     ; Refresh
            86400      ; Retry
            2419200    ; Expire
            604800 )   ; Negative Cache TTL

             IN NS       nuc-00.homelab.kubernerdes.com.

; Rancher Cluster
rancher         IN      A       10.10.13.30
rancher-01      IN      A       10.10.13.31
rancher-02      IN      A       10.10.13.32
rancher-03      IN      A       10.10.13.33
; Observability Cluster
observability           IN      A       10.10.13.40
observability-01        IN      A       10.10.13.41
observability-02        IN       A      10.10.13.42
observability-03        IN       A      10.10.13.43
; Apps Cluster
apps            IN      A       10.10.13.50
apps-01         IN      A       10.10.13.51
apps-02         IN      A       10.10.13.52
apps-03         IN      A       10.10.13.53

; Load Balancer for Harvester Cluster(s) - one LB per Harvester Cluster
; These are the Host Address - define VIP elsewhere
nuc-00-03	IN	A	10.10.13.93

; Hardware Devices in the 1xx range
; NUC cluster (Harvester Edge)
harvester	IN	A	10.10.13.100
nuc-01		IN	A	10.10.13.101
nuc-02		IN	A	10.10.13.102
nuc-03		IN	A	10.10.13.103

nuc-01-kvm	IN	A	10.10.13.111
nuc-02-kvm	IN	A	10.10.13.112
nuc-03-kvm	IN	A	10.10.13.113

; DHCP CIDR 10.10.13.0/24
dhcp-128    IN      A       10.10.13.128
dhcp-129    IN      A       10.10.13.129
dhcp-130    IN      A       10.10.13.130
dhcp-131    IN      A       10.10.13.131
dhcp-132    IN      A       10.10.13.132
dhcp-133    IN      A       10.10.13.133
dhcp-134    IN      A       10.10.13.134
dhcp-135    IN      A       10.10.13.135
dhcp-136    IN      A       10.10.13.136
dhcp-137    IN      A       10.10.13.137
dhcp-138    IN      A       10.10.13.138
dhcp-139    IN      A       10.10.13.139
dhcp-140    IN      A       10.10.13.140
dhcp-141    IN      A       10.10.13.141
dhcp-142    IN      A       10.10.13.142
dhcp-143    IN      A       10.10.13.143
dhcp-144    IN      A       10.10.13.144
dhcp-145    IN      A       10.10.13.145
dhcp-146    IN      A       10.10.13.146
dhcp-147    IN      A       10.10.13.147
dhcp-148    IN      A       10.10.13.148
dhcp-149    IN      A       10.10.13.149
dhcp-150    IN      A       10.10.13.150
dhcp-151    IN      A       10.10.13.151
dhcp-152    IN      A       10.10.13.152
dhcp-153    IN      A       10.10.13.153
dhcp-154    IN      A       10.10.13.154
dhcp-155    IN      A       10.10.13.155
dhcp-156    IN      A       10.10.13.156
dhcp-157    IN      A       10.10.13.157
dhcp-158    IN      A       10.10.13.158
dhcp-159    IN      A       10.10.13.159
dhcp-160    IN      A       10.10.13.160
dhcp-161    IN      A       10.10.13.161
dhcp-162    IN      A       10.10.13.162
dhcp-163    IN      A       10.10.13.163
dhcp-164    IN      A       10.10.13.164
dhcp-165    IN      A       10.10.13.165
dhcp-166    IN      A       10.10.13.166
dhcp-167    IN      A       10.10.13.167
dhcp-168    IN      A       10.10.13.168
dhcp-169    IN      A       10.10.13.169
dhcp-170    IN      A       10.10.13.170
dhcp-171    IN      A       10.10.13.171
dhcp-172    IN      A       10.10.13.172
dhcp-173    IN      A       10.10.13.173
dhcp-174    IN      A       10.10.13.174
dhcp-175    IN      A       10.10.13.175
dhcp-176    IN      A       10.10.13.176
dhcp-177    IN      A       10.10.13.177
dhcp-178    IN      A       10.10.13.178
dhcp-179    IN      A       10.10.13.179
dhcp-180    IN      A       10.10.13.180
dhcp-181    IN      A       10.10.13.181
dhcp-182    IN      A       10.10.13.182
dhcp-183    IN      A       10.10.13.183
dhcp-184    IN      A       10.10.13.184
dhcp-185    IN      A       10.10.13.185
dhcp-186    IN      A       10.10.13.186
dhcp-187    IN      A       10.10.13.187
dhcp-188    IN      A       10.10.13.188
dhcp-189    IN      A       10.10.13.189
dhcp-190    IN      A       10.10.13.190
dhcp-191    IN      A       10.10.13.191
dhcp-192    IN      A       10.10.13.192
dhcp-193    IN      A       10.10.13.193
dhcp-194    IN      A       10.10.13.194
dhcp-195    IN      A       10.10.13.195
dhcp-196    IN      A       10.10.13.196
dhcp-197    IN      A       10.10.13.197
dhcp-198    IN      A       10.10.13.198
dhcp-199    IN      A       10.10.13.199
dhcp-200    IN      A       10.10.13.200
dhcp-201    IN      A       10.10.13.201
dhcp-202    IN      A       10.10.13.202
dhcp-203    IN      A       10.10.13.203
dhcp-204    IN      A       10.10.13.204
dhcp-205    IN      A       10.10.13.205
dhcp-206    IN      A       10.10.13.206
dhcp-207    IN      A       10.10.13.207
dhcp-208    IN      A       10.10.13.208
dhcp-209    IN      A       10.10.13.209
dhcp-210    IN      A       10.10.13.210
dhcp-211    IN      A       10.10.13.211
dhcp-212    IN      A       10.10.13.212
dhcp-213    IN      A       10.10.13.213
dhcp-214    IN      A       10.10.13.214
dhcp-215    IN      A       10.10.13.215
dhcp-216    IN      A       10.10.13.216
dhcp-217    IN      A       10.10.13.217
dhcp-218    IN      A       10.10.13.218
dhcp-219    IN      A       10.10.13.219
dhcp-220    IN      A       10.10.13.220
dhcp-221    IN      A       10.10.13.221
dhcp-222    IN      A       10.10.13.222
dhcp-223    IN      A       10.10.13.223
dhcp-224    IN      A       10.10.13.224
dhcp-225    IN      A       10.10.13.225
dhcp-226    IN      A       10.10.13.226
dhcp-227    IN      A       10.10.13.227
dhcp-228	 IN	 A	 10.10.13.228
dhcp-229	 IN	 A	 10.10.13.229
dhcp-230	 IN	 A	 10.10.13.230
dhcp-231	 IN	 A	 10.10.13.231
dhcp-232	 IN	 A	 10.10.13.232
dhcp-233	 IN	 A	 10.10.13.233
dhcp-234	 IN	 A	 10.10.13.234
dhcp-235	 IN	 A	 10.10.13.235
dhcp-236	 IN	 A	 10.10.13.236
dhcp-237	 IN	 A	 10.10.13.237
dhcp-238	 IN	 A	 10.10.13.238
dhcp-239	 IN	 A	 10.10.13.239
dhcp-240	 IN	 A	 10.10.13.240
dhcp-241	 IN	 A	 10.10.13.241
dhcp-242	 IN	 A	 10.10.13.242
dhcp-243	 IN	 A	 10.10.13.243
dhcp-244	 IN	 A	 10.10.13.244
dhcp-245	 IN	 A	 10.10.13.245
dhcp-246	 IN	 A	 10.10.13.246
dhcp-247	 IN	 A	 10.10.13.247
dhcp-248	 IN	 A	 10.10.13.248
dhcp-249	 IN	 A	 10.10.13.249
dhcp-250	 IN	 A	 10.10.13.250
dhcp-251	 IN	 A	 10.10.13.251
dhcp-252	 IN	 A	 10.10.13.252
dhcp-253	 IN	 A	 10.10.13.253
dhcp-254	 IN	 A	 10.10.13.254

; Application Wildcard Endpoints
*.apps.enclave.kubernerdes.com. 	IN 	A 	10.10.13.40

; Docs hosted at github pages
docs.enclave.kubernerdes.com.   IN      CNAME   jradtke-rgs.github.io.

; Harbor CNAME
harbor.enclave.kubernerdes.com.	IN	CNAME nuc-00.enclave.kubernerdes.com.

