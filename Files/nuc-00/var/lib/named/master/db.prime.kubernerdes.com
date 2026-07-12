$TTL 604800 
$ORIGIN prime.kubernerdes.com. 
@	IN SOA      nuc-00.homelab.kubernerdes.com.  root.kubernerdes.com. ( 
            2026071201 ; Serial
            604800     ; Refresh
            86400      ; Retry
            2419200    ; Expire
            604800 )   ; Negative Cache TTL

             IN NS       nuc-00.homelab.kubernerdes.com.

; Rancher Cluster
rancher         IN      A       10.10.15.30
rancher-01      IN      A       10.10.15.31
rancher-02      IN      A       10.10.15.32
rancher-03      IN      A       10.10.15.33
; Observability Cluster
observability           IN      A       10.10.15.40
observability-01        IN      A       10.10.15.41
observability-02        IN       A      10.10.15.42
observability-03        IN       A      10.10.15.43
; Apps Cluster
apps            IN      A       10.10.15.50
apps-01         IN      A       10.10.15.51
apps-02         IN      A       10.10.15.52
apps-03         IN      A       10.10.15.53

; Load Balancer for Harvester Cluster(s) - one LB per Harvester Cluster
; These are the Host Address - define VIP elsewhere
nuc-00-03	IN	A	10.10.15.93

; Hardware Devices in the 1xx range
; NUC cluster (Harvester Edge)
harvester	IN	A	10.10.15.100
nuc-01		IN	A	10.10.15.101
nuc-02		IN	A	10.10.15.102
nuc-03		IN	A	10.10.15.103

nuc-01-kvm	IN	A	10.10.15.111
nuc-02-kvm	IN	A	10.10.15.112
nuc-03-kvm	IN	A	10.10.15.113

; DHCP CIDR 10.10.15.0/24
dhcp-128    IN      A       10.10.15.128
dhcp-129    IN      A       10.10.15.129
dhcp-130    IN      A       10.10.15.130
dhcp-131    IN      A       10.10.15.131
dhcp-132    IN      A       10.10.15.132
dhcp-133    IN      A       10.10.15.133
dhcp-134    IN      A       10.10.15.134
dhcp-135    IN      A       10.10.15.135
dhcp-136    IN      A       10.10.15.136
dhcp-137    IN      A       10.10.15.137
dhcp-138    IN      A       10.10.15.138
dhcp-139    IN      A       10.10.15.139
dhcp-140    IN      A       10.10.15.140
dhcp-141    IN      A       10.10.15.141
dhcp-142    IN      A       10.10.15.142
dhcp-143    IN      A       10.10.15.143
dhcp-144    IN      A       10.10.15.144
dhcp-145    IN      A       10.10.15.145
dhcp-146    IN      A       10.10.15.146
dhcp-147    IN      A       10.10.15.147
dhcp-148    IN      A       10.10.15.148
dhcp-149    IN      A       10.10.15.149
dhcp-150    IN      A       10.10.15.150
dhcp-151    IN      A       10.10.15.151
dhcp-152    IN      A       10.10.15.152
dhcp-153    IN      A       10.10.15.153
dhcp-154    IN      A       10.10.15.154
dhcp-155    IN      A       10.10.15.155
dhcp-156    IN      A       10.10.15.156
dhcp-157    IN      A       10.10.15.157
dhcp-158    IN      A       10.10.15.158
dhcp-159    IN      A       10.10.15.159
dhcp-160    IN      A       10.10.15.160
dhcp-161    IN      A       10.10.15.161
dhcp-162    IN      A       10.10.15.162
dhcp-163    IN      A       10.10.15.163
dhcp-164    IN      A       10.10.15.164
dhcp-165    IN      A       10.10.15.165
dhcp-166    IN      A       10.10.15.166
dhcp-167    IN      A       10.10.15.167
dhcp-168    IN      A       10.10.15.168
dhcp-169    IN      A       10.10.15.169
dhcp-170    IN      A       10.10.15.170
dhcp-171    IN      A       10.10.15.171
dhcp-172    IN      A       10.10.15.172
dhcp-173    IN      A       10.10.15.173
dhcp-174    IN      A       10.10.15.174
dhcp-175    IN      A       10.10.15.175
dhcp-176    IN      A       10.10.15.176
dhcp-177    IN      A       10.10.15.177
dhcp-178    IN      A       10.10.15.178
dhcp-179    IN      A       10.10.15.179
dhcp-180    IN      A       10.10.15.180
dhcp-181    IN      A       10.10.15.181
dhcp-182    IN      A       10.10.15.182
dhcp-183    IN      A       10.10.15.183
dhcp-184    IN      A       10.10.15.184
dhcp-185    IN      A       10.10.15.185
dhcp-186    IN      A       10.10.15.186
dhcp-187    IN      A       10.10.15.187
dhcp-188    IN      A       10.10.15.188
dhcp-189    IN      A       10.10.15.189
dhcp-190    IN      A       10.10.15.190
dhcp-191    IN      A       10.10.15.191
dhcp-192    IN      A       10.10.15.192
dhcp-193    IN      A       10.10.15.193
dhcp-194    IN      A       10.10.15.194
dhcp-195    IN      A       10.10.15.195
dhcp-196    IN      A       10.10.15.196
dhcp-197    IN      A       10.10.15.197
dhcp-198    IN      A       10.10.15.198
dhcp-199    IN      A       10.10.15.199
dhcp-200    IN      A       10.10.15.200
dhcp-201    IN      A       10.10.15.201
dhcp-202    IN      A       10.10.15.202
dhcp-203    IN      A       10.10.15.203
dhcp-204    IN      A       10.10.15.204
dhcp-205    IN      A       10.10.15.205
dhcp-206    IN      A       10.10.15.206
dhcp-207    IN      A       10.10.15.207
dhcp-208    IN      A       10.10.15.208
dhcp-209    IN      A       10.10.15.209
dhcp-210    IN      A       10.10.15.210
dhcp-211    IN      A       10.10.15.211
dhcp-212    IN      A       10.10.15.212
dhcp-213    IN      A       10.10.15.213
dhcp-214    IN      A       10.10.15.214
dhcp-215    IN      A       10.10.15.215
dhcp-216    IN      A       10.10.15.216
dhcp-217    IN      A       10.10.15.217
dhcp-218    IN      A       10.10.15.218
dhcp-219    IN      A       10.10.15.219
dhcp-220    IN      A       10.10.15.220
dhcp-221    IN      A       10.10.15.221
dhcp-222    IN      A       10.10.15.222
dhcp-223    IN      A       10.10.15.223
dhcp-224    IN      A       10.10.15.224
dhcp-225    IN      A       10.10.15.225
dhcp-226    IN      A       10.10.15.226
dhcp-227    IN      A       10.10.15.227
dhcp-228	 IN	 A	 10.10.15.228
dhcp-229	 IN	 A	 10.10.15.229
dhcp-230	 IN	 A	 10.10.15.230
dhcp-231	 IN	 A	 10.10.15.231
dhcp-232	 IN	 A	 10.10.15.232
dhcp-233	 IN	 A	 10.10.15.233
dhcp-234	 IN	 A	 10.10.15.234
dhcp-235	 IN	 A	 10.10.15.235
dhcp-236	 IN	 A	 10.10.15.236
dhcp-237	 IN	 A	 10.10.15.237
dhcp-238	 IN	 A	 10.10.15.238
dhcp-239	 IN	 A	 10.10.15.239
dhcp-240	 IN	 A	 10.10.15.240
dhcp-241	 IN	 A	 10.10.15.241
dhcp-242	 IN	 A	 10.10.15.242
dhcp-243	 IN	 A	 10.10.15.243
dhcp-244	 IN	 A	 10.10.15.244
dhcp-245	 IN	 A	 10.10.15.245
dhcp-246	 IN	 A	 10.10.15.246
dhcp-247	 IN	 A	 10.10.15.247
dhcp-248	 IN	 A	 10.10.15.248
dhcp-249	 IN	 A	 10.10.15.249
dhcp-250	 IN	 A	 10.10.15.250
dhcp-251	 IN	 A	 10.10.15.251
dhcp-252	 IN	 A	 10.10.15.252
dhcp-253	 IN	 A	 10.10.15.253
dhcp-254	 IN	 A	 10.10.15.254

; Application Wildcard Endpoints
*.apps.prime.kubernerdes.com. 	IN 	A 	10.10.15.40

; Docs hosted at github pages
docs.prime.kubernerdes.com.   IN      CNAME   jradtke-rgs.github.io.

; Harbor CNAME
harbor.prime.kubernerdes.com.	IN	CNAME nuc-00.prime.kubernerdes.com.

