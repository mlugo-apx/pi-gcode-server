#!/usr/bin/python3
import sys
import subprocess
import shlex
import glob

def scp_files(file_paths):
    # Hard-coded configurations
    port = "9702"
    remote_user = "milugo"
    remote_host = "localhost"
    remote_path = "/mnt/usb_share"

    for file_path in file_paths:
        # Constructing the SCP command with proper shell quoting
        quoted_file_path = shlex.quote(file_path)
        scp_command = f"scp -P {port} {quoted_file_path} {remote_user}@{remote_host}:{remote_path}"

        # Running the SCP command
        try:
            subprocess.run(scp_command, shell=True, check=True)
            print(f"File '{file_path}' successfully transferred.")
        except subprocess.CalledProcessError as e:
            print(f"Error transferring file '{file_path}': {e}")

def ssh_and_commands():
    # Hard-coded configurations
    port = "9702"
    remote_user = "milugo"
    remote_host = "localhost"

    # Check if usbhid module is built-in
    is_builtin = subprocess.run("lsmod | grep usbhid", shell=True, stdout=subprocess.PIPE).stdout.decode()
    if "usbhid" not in is_builtin:
        # Constructing the SSH commands to reload usbhid if it's not built-in
        ssh_commands = [
            #f'ssh -p {port} {remote_user}@{remote_host} "sudo usb_modeswitch -v 1d6b -p 0002 -b 001 -d 001"'
            f'ssh -p {port} {remote_user}@{remote_host} "sudo reboot"'
        ]
    else:
        print("USB-PI has been reloaded")
        #print("usbhid module is built-in. Skipping reloading.")

    # Running the SSH commands if needed
    try:
        for command in ssh_commands:
            subprocess.run(command, shell=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error executing SSH command: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <file_path1> [<file_path2> ...]")
    else:
        file_paths = []
        for arg in sys.argv[1:]:
            file_paths.extend(glob.glob(arg))  # Handle wildcards and expand paths
        if not file_paths:
            print("No matching files found.")
        else:
            scp_files(file_paths)
            ssh_and_commands()
