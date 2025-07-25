#!/usr/bin/env python3
"""
Norns Agent Integration
Python wrapper for AI agent integration with Norns runtime via SSH and maiden repl
"""

import paramiko
import json
import shlex
import io
import sys
import os
from typing import Dict, Any, Optional

class NornsAgent:
    def __init__(self, host: str = "norns.local", username: str = "we", password: str = "sleep"):
        """Initialize connection to Norns device"""
        self.host = host
        self.username = username
        self.password = password
        self.client = None
        self.connected = False
        
    def connect(self) -> bool:
        """Establish SSH connection to Norns device"""
        try:
            self.client = paramiko.SSHClient()
            self.client.load_system_host_keys()
            self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.client.connect(self.host, username=self.username, password=self.password)
            self.connected = True
            print(f"✅ Connected to Norns device at {self.host}")
            return True
        except Exception as e:
            print(f"❌ Failed to connect to Norns device: {e}")
            return False
    
    def disconnect(self):
        """Close SSH connection"""
        if self.client:
            self.client.close()
            self.connected = False
    
    def eval_lua(self, code: str) -> str:
        """Execute Lua code in Norns runtime via maiden repl"""
        if not self.connected:
            raise Exception("Not connected to Norns device")
        
        # Sanitize code for safety
        if self._is_unsafe_code(code):
            raise Exception("Unsafe code detected - rejected for security")
        
        try:
            # Escape the code for shell execution
            escaped_code = shlex.quote(code)
            cmd = f"echo {escaped_code} | maiden repl"
            
            stdin, stdout, stderr = self.client.exec_command(cmd)
            result = stdout.read().decode('utf-8')
            error = stderr.read().decode('utf-8')
            
            if error:
                print(f"Warning: {error}")
            
            return result.strip()
        except Exception as e:
            raise Exception(f"Failed to execute Lua code: {e}")
    
    def _is_unsafe_code(self, code: str) -> bool:
        """Check if code contains potentially unsafe operations"""
        unsafe_patterns = [
            'os.execute',
            'io.open',
            'require("io")',
            'require("os")',
            'file.write',
            'file:write',
            'dofile',
            'loadfile',
            'loadstring',
            'pcall(os.execute',
            'pcall(io.open',
        ]
        
        code_lower = code.lower()
        for pattern in unsafe_patterns:
            if pattern in code_lower:
                return True
        return False
    
    def get_state(self) -> Dict[str, Any]:
        """Get current state of Norns device"""
        state_code = '''
        return json.encode({
            output_level = params:get("output_level"),
            engine_ready = engine.ready,
            clock_beats = clock.get_beats(),
            clock_tempo = clock.get_tempo(),
            screen_dirty = screen.dirty or false,
            midi_ports = #midi.vports
        })
        '''
        
        try:
            result = self.eval_lua(state_code)
            return json.loads(result)
        except Exception as e:
            print(f"Warning: Could not get state: {e}")
            return {}
    
    def run_test(self, test_file: str) -> Dict[str, Any]:
        """Run a test file on the Norns device"""
        if not os.path.exists(test_file):
            raise Exception(f"Test file not found: {test_file}")
        
        # Read the test file
        with open(test_file, 'r') as f:
            test_code = f.read()
        
        # Execute the test
        result = self.eval_lua(test_code)
        
        return {
            'test_file': test_file,
            'result': result,
            'success': '✅' in result or 'PASSED' in result,
            'error': '❌' in result or 'FAILED' in result
        }
    
    def deploy_and_test(self, local_path: str, remote_path: str = "~/dust/code/Foobar") -> Dict[str, Any]:
        """Deploy code and run tests"""
        try:
            # Deploy using rsync
            rsync_cmd = f"rsync -av --exclude='.git' {local_path}/ {self.username}@{self.host}:{remote_path}"
            print(f"Deploying to {self.host}...")
            os.system(rsync_cmd)
            
            # Run tests
            test_results = []
            
            # Test 1: Runtime tests
            runtime_test = self.run_test("test/norns_runtime_spec.lua")
            test_results.append(runtime_test)
            
            # Test 2: Busted tests (if available)
            try:
                busted_test = self.run_test("test/norns_busted_spec.lua")
                test_results.append(busted_test)
            except Exception as e:
                print(f"Busted tests not available: {e}")
            
            return {
                'deployment': 'success',
                'tests': test_results,
                'all_passed': all(t['success'] for t in test_results)
            }
            
        except Exception as e:
            return {
                'deployment': 'failed',
                'error': str(e),
                'all_passed': False
            }

def main():
    """Main function for command-line usage"""
    if len(sys.argv) < 2:
        print("Usage: python norns_agent.py <command> [args...]")
        print("Commands:")
        print("  eval <lua_code>     - Execute Lua code")
        print("  state               - Get device state")
        print("  test <test_file>    - Run a test file")
        print("  deploy <local_path> - Deploy and test")
        return
    
    command = sys.argv[1]
    
    # Load environment variables
    host = os.getenv('NORNS_HOST', 'norns.local')
    username = os.getenv('NORNS_USER', 'we')
    password = os.getenv('NORNS_PASS', 'sleep')
    
    agent = NornsAgent(host, username, password)
    
    if not agent.connect():
        sys.exit(1)
    
    try:
        if command == 'eval' and len(sys.argv) > 2:
            code = ' '.join(sys.argv[2:])
            result = agent.eval_lua(code)
            print(result)
            
        elif command == 'state':
            state = agent.get_state()
            print(json.dumps(state, indent=2))
            
        elif command == 'test' and len(sys.argv) > 2:
            test_file = sys.argv[2]
            result = agent.run_test(test_file)
            print(json.dumps(result, indent=2))
            
        elif command == 'deploy' and len(sys.argv) > 2:
            local_path = sys.argv[2]
            result = agent.deploy_and_test(local_path)
            print(json.dumps(result, indent=2))
            
        else:
            print("Invalid command or missing arguments")
            sys.exit(1)
            
    finally:
        agent.disconnect()

if __name__ == "__main__":
    main() 