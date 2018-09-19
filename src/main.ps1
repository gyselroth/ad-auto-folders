try {
  $config=Get-Content -Path .\config.json -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Write-Error "failed to decode config config.json";
  Write-Error $_.Exception
  exit 127
}

$levels = @{
  "error"=0;
  "warn"=1;
  "info"=2;
  "debug"=3;
}

$global:mail = ""

function log($level, $message) {
  $log = "$(Get-Date); "+$level+"; "+$message;
  
  $from = $levels[$config.log.stdout.level]
  if($config.log.stdout.enabled -and $levels[$level] -le $levels[$config.log.stdout.level]) {
    write-host $log;
  }
  
  $from = $levels[$config.log.file.level]
  if($config.log.file.enabled -and $levels[$level] -le $levels[$config.log.file.level] -and $config.log.file.path) {
    $log >> $config.log.file.path
  }
  
  if($config.log.mail.enabled -and $levels[$level] -le $levels[$config.log.mail.level]) {
    $global:mail = $global:mail + $log+"`r`n" 
  }
}

function modAcl($path, $folder, $object) {
  log "debug" ("update acl rules for folder "+$path)
  
  try {
    $list = (Get-Item $path).GetAccessControl('Access')

    foreach($rule in $folder.acl) {
      if($rule.resource -ne "self") {
        write-host $rule
        $resource = Get-ADObject $rule.resource
      } else {
        $resource = $object
      }
      
      if($resource.SamAccountName) {
        $resource = $resource.SamAccountName
      } else {
        $resource = $resource.Name
      }

      log "debug" ("set acl rule "+$resource+" "+$rule.privilege+" "+$rule.inheritance+" "+$rule.propagation+" "+$rule.type+" for path "+$path);
      $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($resource, $rule.privilege, $rule.inheritance, $rule.propagation, $rule.type)
      $list.SetAccessRule($rule)
    }
    
    Set-Acl -path $path -AclObject $list
  } catch {
    log "error" ("failed update acl for folder "+$path+", exception="+$_.Exception.Message+"; item="+$_.Exception.ItemName)
  }
}

function mkdir($folder, $object, $root, $name) {
    $path = Join-Path $root -childpath $name;
  log "debug" ("verify if folder "+$path+" exists")
    
    if (Test-Path $path) {
    log "debug", ("path "+$path+" already exists")
  } else {
        try {
      log "info" ("create folder "+$path)
            New-Item $path -type directory
        } catch {
      log "error" ("failed create directory "+$path+", exception="+$_.Exception.Message+"; item="+$_.Exception.ItemName)
        }
  }
  
  modAcl $path $folder $object
  
  foreach($sub in $folder.subs) {
    log "debug" ("create sub folder "+$sub.name+" in folder "+$path)
    mkdir $sub $object $path $sub.name
  }
}

function prepareFolder($folder) {
  try {
    log "debug" ("search ad with base "+$folder.base+" and filter "+$folder.filter)
    $objects = Get-ADObject -SearchScope $folder.scope -SearchBase $folder.base -Filter $folder.filter
    return $objects;
  } catch {
    log "error" ("failed search ad with base "+$folder.base+" and filter "+$folder.filter+", exception="+$_.Exception.Message+"; item="+$_.Exception.ItemName)
    return @()
  }
}

function archive($folder, $found) {
  try {
    if($folder.archive) {
      log "info" ("check folder "+$folder.id+" for archive")
      
      if($found.Count -eq 0) {
        log "warn" ("check folder "+$folder.id+" for archive")
        return;
      }
      
      $base = $folder.root+"\*"
      foreach ($node in get-ChildItem $base) {
        $path = Join-Path $folder.root -childpath $node.name
      
        if($path -eq $folder.archive_root) {
          continue;
        }
        
        log "debug" ("check folder "+$path+" for archive move")
      
        if($found.Contains($node.name)) {
          log "debug" ("folder "+$path+" is not meant to archive")
        } else {
          log "info" ("move folder "+$path+" to archive "+$folder.archive_root)   

          if(!(Test-Path $folder.archive_root)) {
            New-Item $folder.archive_root -type directory
          }
          
          $dest = Join-Path $folder.archive_root -childpath $node.name
          Move-Item -Path $path -Destination $dest
        }
      }     
    } else {
      log "info" ("archive is disabled for folder "+$folder.id)
    }
  } catch {
    log "error" ("failed to execute archive exception="+$_.Exception.Message+"; item="+$_.Exception.ItemName)
  }
}

foreach($folder in $config.folders) {
  log "info", ("prepare folder "+$folder.id);
  $objects = prepareFolder $folder
  log "info" ("found "+$objects.Count+" objects for folder "+$folder.id);
  
  $found = @();
  
  foreach($object in $objects) {
    if(!$object.DistinguishedName) {
      continue
    }
        
    $found += $object.Name
    log "debug" ("sync folder for ad object "+$object.DistinguishedName+" in folder "+$folder.id)
    mkdir $folder $object $folder.root $object.name
  }
  
  archive $folder $found
}

if($config.log.mail.enabled -and $global:mail -ne "") {
    $password = ConvertTo-SecureString $config.log.mail.smtp.password -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential $config.log.mail.smtp.username, $password
  
  foreach($receiver in $config.log.mail.recipients) {
    Send-MailMessage -Credential $credentials -From $config.log.mail.from -To $receiver -Subject $config.log.mail.subject -SmtpServer $config.log.mail.smtp.host -Body $global:mail -Port $config.log.mail.smtp.port -Usessl
  }
}
