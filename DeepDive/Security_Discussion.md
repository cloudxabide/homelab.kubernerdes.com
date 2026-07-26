# Security Discussion

I get the feeling this will end up being a somewhat lengthy doc with several sections.

## Distroless (or "no Shell Containers)
During a discussion with a customer new to Kubernetes (and somewhat new to containers)  
customer: "Distroless remove the ability for someone to hack in since there is no shell"  
me: ...nods head, while thinking... "well, not exactly"  

But.. I did not have a narrative to explain why I was not (entirely) in agreement.  

### Narrative around Distroless containers and NeuVector (SUSE Security) 

Let's review how NeuVector helps mitigate these types of attacks

Attackers can exploit shell-less (often called distroless) Kubernetes containers by shifting their focus from traditional OS-level commands to application-level vulnerabilities, memory manipulation, and Kubernetes-specific misconfigurations. While removing shells like `bash` or `sh` significantly reduces the attack surface by breaking many automated exploit scripts, it does not make the container immune to compromise.

Here are the primary methods attackers use to exploit and pivot from Kubernetes containers that lack a traditional shell.

1. Living off the Application (LotA)
When OS-level tools like `curl`, `wget`, or `bash` are missing, attackers leverage the runtime environment of the application itself. If the container runs a Node.js, Python, Java, or Ruby application, the attacker can use the language's built-in libraries to achieve their goals.
Native Code Execution: Instead of trying to spawn a shell process, an attacker with Remote Code Execution (RCE) will execute code directly within the interpreter. For example, in a Python application, they can import the `socket` and `subprocess` modules to create a reverse connection and manipulate files directly through Python commands.
Data Exfiltration: Attackers can write scripts within the compromised application's language to read sensitive local files and send them out over HTTP using native libraries (e.g., `urllib` in Python or `http` in Node.js).
2. Exploiting Application Vulnerabilities
The lack of a shell does not patch the underlying software. Attackers routinely exploit web application vulnerabilities to gain access to the container's environment or the broader Kubernetes cluster.
Server-Side Request Forgery (SSRF): This is one of the most critical vulnerabilities in a shell-less environment. An attacker can force the application to make HTTP requests on their behalf. In Kubernetes, this can be used to query the local Kubelet API, access unauthenticated internal microservices, or hit cloud provider metadata services (like `169.254.169.254`) to steal IAM roles and tokens.
Path Traversal / Local File Inclusion (LFI): Even without executing commands, an attacker can use LFI to read sensitive files mounted into the container.
Deserialization Flaws: Insecure deserialization allows attackers to inject malicious objects into memory, which can lead to direct code execution within the context of the application runtime, bypassing the need for OS binaries.
3. Kubernetes Service Account Token Abuse
Every Kubernetes pod typically has a Service Account token mounted by default, usually located at `/var/run/secrets/kubernetes.io/serviceaccount/token`.
Token Extraction: Using a path traversal vulnerability or by exploiting the application's read capabilities, an attacker can extract this JWT (JSON Web Token).
External API Interaction: Once the token is exfiltrated, the attacker does not need a shell in the container. They can configure their own local `kubectl` using the stolen token and communicate directly with the Kubernetes API server from the outside, assuming the API server is exposed or they have a network route.
4. Dropping Statically Compiled Binaries
If an attacker finds an arbitrary file upload or file write vulnerability, the absence of a shell is only a temporary hurdle.
Bring Your Own Land (BYOL): Attackers can compile their own tools (like a standalone `busybox` binary, a Go-based reverse shell, or `kubectl`) statically. A statically compiled binary contains all necessary dependencies and does not rely on the container's missing OS libraries.
Execution: Once the binary is written to a writable directory (such as `/tmp`), the attacker triggers its execution through the application's vulnerabilities (like a deserialization flaw or a custom script injection).
5. Memory-Based and Fileless Execution
Advanced attackers can bypass the filesystem entirely, which is particularly effective against containers that enforce read-only root filesystems alongside a distroless architecture.
Buffer Overflows and Shellcode: If the application is written in C/C++ or uses vulnerable native bindings, attackers can exploit memory corruption vulnerabilities. They can inject shellcode directly into memory to perform system calls (syscalls) without ever touching a shell binary.
Memfd_create: Attackers can use Linux system calls like `memfd_create` to create anonymous files in RAM, write a malicious ELF payload into that memory space, and execute it directly, leaving no trace on the disk.
6. Kernel Exploitation and Container Breakouts
Containers share the host node's kernel. The tools present inside the container are irrelevant if the attacker can exploit a vulnerability in the underlying Linux kernel or the container runtime.
Kernel Vulnerabilities: Flaws like "Dirty Pipe" (CVE-2022-0847) or eBPF vulnerabilities allow an attacker to manipulate kernel memory or escalate privileges. An application-layer RCE can be used to trigger a kernel exploit, breaking out of the container and gaining root access to the Kubernetes worker node.
Runtime Escapes: Vulnerabilities in container runtimes (like `runc` or `containerd`) can be exploited to escape the namespace isolation. Once on the underlying host node, the attacker has access to a full operating system shell and the kubelet credentials.
Summary
Removing shells from Kubernetes containers is an excellent defense-in-depth strategy, but it is not a silver bullet. Attackers exploit shell-less containers by pivoting to application-layer attacks, leveraging the application's native runtime languages (Python, Node, Java), extracting Kubernetes Service Account tokens via file inclusion, dropping statically compiled binaries, or targeting the shared host kernel. Comprehensive security requires combining distroless images with read-only root filesystems, strict network policies, dropping unnecessary Linux capabilities, and continuously patching application dependencies.

           
SUSE NeuVector protects distroless containers by applying a strict Zero Trust security model at runtime, operating independently of the container's internal operating system or available utilities. Because distroless containers already remove the OS-level attack surface (like shells and package managers), NeuVector focuses on securing the application itself and its interactions with the network, file system, and host kernel.

NeuVector achieves this protection by establishing a behavioral baseline of what the container is supposed to do, and automatically blocking anything else. Here is how NeuVector specifically mitigates the attacks used against shell-less containers.

1. Zero Trust Process Profiling
When a distroless container is deployed, NeuVector enters a "Discover" mode where it automatically learns the normal behavior of the application, including exactly which processes are expected to run. It then builds a strict allow-list.
Blocking Statically Compiled Binaries: If an attacker exploits a vulnerability to drop and execute a statically compiled binary (Bring Your Own Land), NeuVector detects that this new process is not part of the established baseline.
Preventing Memory Executions: If an attacker uses memory-based exploitation (like injecting shellcode or using `memfd_create`), NeuVector identifies the anomalous process execution or unexpected system calls and blocks the action before it can execute, regardless of whether a shell exists.
2. Layer 7 Network Micro-Segmentation
NeuVector features a patented Deep Packet Inspection (DPI) engine that inspects network traffic at the application layer (Layer 7). It does not just look at IP addresses and ports; it understands the actual protocols being used, such as HTTP, DNS, gRPC, or MySQL.
Defeating SSRF and C2 Callbacks: If an attacker exploits Server-Side Request Forgery (SSRF) to query the cloud metadata service or attempts to establish a reverse connection to a Command and Control (C2) server, NeuVector blocks it. The platform ensures the container can only talk to approved internal services or external domains using approved protocols.
Preventing Lateral Movement: Even if an attacker steals a Service Account token via a file read vulnerability, NeuVector's network rules can prevent the compromised pod from communicating with the Kubernetes API server if that communication was not baselined as normal behavior.
3. File System Monitoring (FIM)
While distroless containers strip away unnecessary files, applications often still require writable directories (like `/tmp` or persistent volumes) to function. Attackers use these writable areas to stage payloads or exfiltrate data.
Unauthorized File Modifications: NeuVector continuously monitors the container's file system for unauthorized changes. If an attacker attempts to write a malicious script, modify configuration files, or tamper with application libraries, NeuVector detects the file activity.
Automated Blocking: In "Protect" mode, NeuVector can be configured to block unauthorized file writes or alert security teams immediately, neutralizing the attacker's ability to establish persistence or stage further attacks.
4. Web Application Firewall (WAF) and DLP
NeuVector includes a built-in container-native Web Application Firewall and Data Loss Prevention (DLP) capabilities. This inspects the payload of incoming and outgoing network traffic directly at the pod level.
Stopping App-Level Exploits: Before an attacker can even attempt to exploit a deserialization flaw or a path traversal vulnerability in a distroless container, NeuVector's WAF can identify and block the malicious payloads (e.g., OWASP Top 10 attacks) embedded in the HTTP requests.
Data Exfiltration Prevention: If an attacker manages to read sensitive data (like a database password or a private key) using the application's native language, NeuVector's DLP engine can detect sensitive data patterns in the outbound network traffic and drop the packets.
5. Host and Kernel Protections
Because containers share the underlying worker node's kernel, a kernel exploit can allow an attacker to completely bypass the distroless restrictions. NeuVector monitors the host node itself alongside the containers.
Privilege Escalation Detection: NeuVector monitors for suspicious system calls, privilege escalations, and container breakout attempts. If an attacker leverages an application vulnerability to trigger a kernel exploit (like Dirty Pipe), NeuVector can detect the anomalous kernel activity and isolate the compromised pod.
Summary
Distroless containers remove the easy tools attackers use, but they do not secure the application itself. NeuVector bridges this gap by enveloping the distroless container in a Zero Trust net. By enforcing strict process baselines, performing deep packet inspection on network traffic, monitoring file writes, and intercepting application-layer attacks, NeuVector ensures that even if an application vulnerability exists, the attacker cannot pivot, execute unauthorized code, or exfiltrate data. 

## TODO
Need to improve teh intro for the narrative section
