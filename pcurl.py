#!/usr/bin/python

import os
import sys
import stat
import time
import Queue
import getopt
import threading
import subprocess
 
numThreads = 1
inputList  = sys.stdin
outputDir  = '.'
megOnly    = False
processStartTime = time.time()
showProgress = False

try:
  opts,args = getopt.getopt(sys.argv[1:], "hi:j:o:Mp")
except getopt.GetoptError:
  raise
for opt,val in opts:
  if opt == '-h':
    print 'help'
    sys.exit(0)
  elif opt == '-i':
    if val == '-': inputList = sys.stdin
    else: inputList = open(val)
  elif opt == '-j':
    numThreads = int(val)
  elif opt == '-o':
    if not os.path.exists(val):
      print '%s is not a valid directory' % val
      sys.exit(1)
    outputDir = val
  elif opt == '-M':
    megOnly = True
  elif opt == '-p':
    showProgress = True

def humansize(size, K):
  if megOnly:
    return '%7.2lfM' % (size/float(K)**2)
  i = -1
  while size > 2.*K:
    size /= float(K)
    i += 1
  suffix = ''
  if i >= 0:
    suffix = '%c' % 'KMGTP'[i]
  return '%7.2lf%s' % (size, suffix)

def humantime(dur):
  if megOnly:
    return '%9d' % dur

  minutes = dur / 60
  seconds = dur % 60
  hours   = minutes / 60
  minutes = minutes % 60
  return '%02d:%02d:%02d' % (hours, minutes, seconds)
  
  
def filesize(fn):
  size = os.stat(fn)[stat.ST_SIZE]
  return '%sB' % humansize(size, 1024)

def dlrate(bytes, duration):
  return '%sbps' % humansize(bytes * 8. / duration, 1000)

def dirsize():
  return sum(map(lambda f: os.stat(os.path.join(outputDir, f))[stat.ST_SIZE], os.listdir(outputDir))) 

jobs = Queue.Queue()
for fn in inputList.readlines():
	jobs.put(fn.strip())

filesDown  = 0
filesTotal = jobs.qsize()

class ShowRate(threading.Thread):
  def __init__(self):
    threading.Thread.__init__(self)
    self.startSize = dirsize()
    self.startTime = time.time()


  def run(self):
    while True:
      time.sleep(1)
      dsize = dirsize()
      bytes = dsize - self.startSize
      dur   = time.time() - self.startTime
      rate  = humansize(bytes * 8. / dur, 1000)
      print '> %12d (%9sB) in %9s ; %9sbps' % (bytes, humansize(bytes, 1024)
                                       , humantime(time.time() - processStartTime)
                                       , rate)
      if filesDown == filesTotal:
        break

      # comment this out to make rates cummulative
      #self.startSize = dirsize
      #self.startTime = time.time()
      
ASCP_CMD = "ascp -TQ -l%(rate)s -G %(writesz)s -Z %(mtu)s " \
           + "-i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh " \
           + "--mode recv --user anonftp --host %(host)s -L . -q " \
           + "%(file)s %(dest)s"

CURL_EXEC = os.environ.get('CURL_EXEC', 'curl')
CURL_CMD = CURL_EXEC + " -s ftp://%(host)s%(file)s -o %(dest)s/%(base)s"

ARIA_CMD = "aria2c --quiet --dir=%(dest)s --file-allocation=none ftp://%(host)s%(file)s"

# HOSTS = [ 'ftp-trace.ncbi.nlm.nih.gov' ]

HOSTS = [ '130.14.250.7'
        , '130.14.250.10'
        , '130.14.250.11'
        , '130.14.250.12'
        , '130.14.250.13'
        ]

class Runner(threading.Thread):
  def __init__(self, index):
    threading.Thread.__init__(self)
    self.index = index

  def run(self):
    global filesDown
    while not jobs.empty():
      path = jobs.get_nowait()
      fn   = os.path.basename(path)
      cmd  = CURL_CMD % \
             { 'rate' :   '10g'
             , 'writesz': '8M'
             , 'mtu' :    '9000'
             , 'host':    HOSTS[self.index % len(HOSTS)]
             , 'file':    path
             , 'base':    os.path.basename(path)
             , 'dest':    outputDir
             }
      starttime = time.time()
      if not os.path.exists(os.path.join(outputDir, fn)):
         print "# %s" % cmd
         os.system(cmd)
      filesDown += 1
      if os.path.exists(os.path.join(outputDir, fn)):
         print '[ %5d of %5d ] %s downloaded. %9s in %4.1lfs' % (
                  filesDown,
                  filesTotal,
                  os.path.join(outputDir, fn), 
                  filesize(os.path.join(outputDir, fn)), 
                  time.time() - starttime)
      else:
         print '%s failed.' % path
      

if showProgress:
   ShowRate().start()

initSize  = dirsize()
startTime = time.time()

threads = [ ]
first = True
for i in range(numThreads):
   threads.append(Runner(i))
   threads[-1].start()

for t in threads:
   t.join()

finalSize = dirsize()
stopTime  = time.time()
print "Downloaded %sB from %s in %s.  Average rate: %s" % \
   ( humansize(finalSize - initSize, 1024)
   , inputList.name 
   , humantime(stopTime - startTime)
   , dlrate(finalSize - initSize, stopTime - startTime))
