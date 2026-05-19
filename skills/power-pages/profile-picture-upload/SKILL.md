---
name: profile-picture-upload
description: >
  Enable profile picture upload on Power Pages Code Sites v2 using the platform's
  built-in Profile/ShowImage feature. Includes the critical CSS fix for the Bootstrap
  modal leak that causes duplicate photos.
version: 1.0.0
author: Marc
triggers:
  - "add profile picture"
  - "profile photo upload"
  - "avatar upload"
  - "two photos on profile"
  - "duplicate profile image"
  - "profile picture not working"
  - "entityimage upload"
---

# Profile Picture Upload — Power Pages Code Sites v2

## Overview

Enable authenticated users to upload/change their profile picture on the Profile page.
Uses the platform's **built-in** `Profile/ShowImage` feature — zero custom JavaScript needed.

## Prerequisites

- Power Pages Code Site v2 deployed and running
- Entra ID authentication configured
- Contact table with `entityimage` column (exists by default)
- `Webapi/contact/enabled` = `true` and `Webapi/contact/fields` = `*`
- Post-deploy patch pipeline (Header/Footer web templates)

## Step 1: Create Site Setting

Create `Profile/ShowImage` = `true` via Dataverse API:

```powershell
$envUrl  = "https://YOUR_ORG.crm4.dynamics.com"
$siteId  = "YOUR-SITE-ID"
$baseUri = "$envUrl/api/data/v9.2"
$token   = az account get-access-token --resource $envUrl --query accessToken -o tsv
$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

# Check if already exists
$filter = "powerpagecomponenttype eq 9 and name eq 'Profile/ShowImage' and _powerpagesiteid_value eq $siteId"
$existing = (Invoke-RestMethod -Uri "$baseUri/powerpagecomponents?`$filter=$filter&`$select=powerpagecomponentid" -Headers $headers).value

if ($existing.Count -eq 0) {
    $body = @{
        name                         = "Profile/ShowImage"
        powerpagecomponenttype       = 9
        content                      = (@{ value = "true"; websiteid = $siteId } | ConvertTo-Json -Compress)
        "powerpagesiteid@odata.bind" = "/powerpagesites($siteId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$baseUri/powerpagecomponents" -Headers $headers -Method Post -Body $body
    Write-Host "Created Profile/ShowImage = true"
} else {
    Write-Host "Profile/ShowImage already exists"
}
```

## Step 2: Restart Site

Required for the platform to pick up the new setting.

## Step 3: Fix the Bootstrap Modal CSS Leak

### The Problem

The platform renders a `.profile-info` card containing:
- `img#profilePictureUploaded` — the inline clickable thumbnail (correct)
- `div#ModalToChangeProfilePicture.modal.fade` — a Bootstrap 5 modal with a second photo, upload/remove buttons, and save/close buttons

The modal **leaks visibly** because the platform's `.profile-info { display: flex !important }` overrides Bootstrap's `.modal { display: none }`. This causes:
- **Two circular photos** stacked vertically
- **Two blank buttons** (Save/Close from the modal, with invisible text on dark backgrounds)

### The Fix

Add this CSS to the Header web template (via post-deploy patch):

```css
/* ========== PROFILE PICTURE — Modal Leak Fix ========== */

/* CRITICAL: Force modal hidden until Bootstrap adds .show on click */
body:has(.page-header) #ModalToChangeProfilePicture:not(.show){display:none!important}

/* Style the modal when it opens (dark theme) */
body:has(.page-header) #ModalToChangeProfilePicture.show .modal-content{
  background:var(--zcb)!important;
  border:1px solid var(--zcbd)!important;
  border-radius:var(--zrl)!important
}
body:has(.page-header) #ModalToChangeProfilePicture.show .modal-header{
  background:linear-gradient(135deg,rgba(0,217,126,.08) 0%,rgba(0,217,126,.03) 100%)!important;
  border-bottom:1px solid var(--zcbd)!important
}
body:has(.page-header) #ModalToChangeProfilePicture.show .btn-primary{
  color:var(--zn)!important
}
body:has(.page-header) #ModalToChangeProfilePicture.show .btn-withoutborder{
  color:#fff!important;
  background:rgba(0,217,126,.15)!important;
  border:1px solid rgba(0,217,126,.3)!important;
  border-radius:8px!important;
  padding:8px 16px!important;
  margin:4px!important
}

/* Style the inline clickable photo container */
body:has(.page-header) .profilePictureContainer{
  display:flex!important;
  flex-direction:column!important;
  align-items:center!important;
  gap:12px!important;
  padding:24px!important;
  background:linear-gradient(145deg,rgba(18,42,58,.95) 0%,rgba(10,31,46,.9) 100%)!important;
  border:1px solid var(--zcbd)!important;
  border-radius:var(--zrl)!important;
  box-shadow:var(--zsl),var(--zcg)!important;
  margin-bottom:16px!important;
  width:auto!important;
  height:auto!important;
  text-decoration:none!important
}

/* Style the actual photo */
body:has(.page-header) .profilePictureContainer img.havingProfilePicture{
  width:120px!important;
  height:120px!important;
  border-radius:50%!important;
  border:3px solid var(--zg)!important;
  object-fit:cover!important;
  box-shadow:0 4px 16px rgba(0,217,126,.3),0 0 0 6px rgba(0,217,126,.08)!important;
  background:var(--zn)!important;
  transition:transform .3s,box-shadow .3s!important
}
body:has(.page-header) .profilePictureContainer img.havingProfilePicture:hover{
  transform:scale(1.05)!important;
  box-shadow:0 6px 20px rgba(0,217,126,.4),0 0 0 8px rgba(0,217,126,.12)!important
}

/* Edit pencil overlay */
body:has(.page-header) .profilePictureContainer .edit{
  color:#fff!important;font-size:13px!important;opacity:.7!important;transition:opacity .2s!important
}
body:has(.page-header) .profilePictureContainer:hover .edit{opacity:1!important}

/* Name text beside photo */
body:has(.page-header) .profile-info .fullName{
  font-family:'Barlow',sans-serif!important;font-weight:700!important;
  font-size:20px!important;color:#fff!important;display:flex!important;align-items:center!important
}
body:has(.page-header) .profile-info{flex-direction:column!important}
```

## Anti-Patterns (DO NOT DO)

| Anti-Pattern | Why It Fails |
|---|---|
| Custom avatar JS fetching `entityimage` via `/_api/contacts` | Creates duplicate photo; unnecessary since platform handles display |
| CSS selector `img[src*="entityimage"]` | Matches BOTH the inline photo AND the modal photo |
| CSS selector `img[src*="ContactProfileImage"]` | Same problem — matches both images |
| Injecting custom `#zava-avatar-container` | Creates a third photo element |
| Targeting `.profile-photo` or `.entity-image` containers | These classes don't exist in the v2 Code Sites profile page |
| Broad sidebar button selectors (`.col-lg-4 .btn`) | Matches modal buttons that should be hidden |

## Platform HTML Structure (Reference)

```html
<div class="card mb-3 profile-info">
  <div class="card-body">
    <div class="row">
      <!-- Clickable photo — SHOWS -->
      <a class="profilePictureContainer editProfilePicture col-3" 
         data-bs-target="#ModalToChangeProfilePicture" data-bs-toggle="modal">
        <img id="profilePictureUploaded" class="havingProfilePicture" 
             src=".../Image/download.aspx?Entity=contact&Attribute=entityimage&Id=..." />
        <span id="noProfilePictureUploaded" class="havingNoProfilePicture" hidden>CW</span>
        <div class="edit"><span class="fa fa-pencil"></span></div>
      </a>

      <!-- Modal — MUST BE HIDDEN until .show is added -->
      <div class="modal fade" id="ModalToChangeProfilePicture">
        <div class="modal-dialog profilePicModal">
          <div class="modal-content">
            <div class="modal-body">
              <div class="modal-maincontent-container">
                <div class="image-container">
                  <img id="profilepic" class="profile-pic-onmodal" src="..." />
                </div>
                <div class="buttons-for-profile">
                  <button id="buttonforupload" class="btn btn-withoutborder">Upload</button>
                  <button id="removebutton" class="btn btn-withoutborder">Remove</button>
                  <button id="savebutton" class="btn btn-primary" disabled>Save</button>
                  <button class="btn btn-default" data-bs-dismiss="modal">Close</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="fullName col-9">Chris Walker</div>
    </div>
  </div>
</div>
```

## Verification Checklist

- [ ] One circular photo visible on profile page (not two)
- [ ] No blank buttons visible on the page
- [ ] Clicking the photo opens a modal with upload/remove/save/close
- [ ] Modal is styled with dark theme (if using dark design system)
- [ ] Uploading a new photo works and persists after page refresh
- [ ] Photo appears in Dataverse contact record's `entityimage` column
