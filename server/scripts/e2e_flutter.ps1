$ErrorActionPreference = 'Stop'
$base = 'http://localhost:3000/api'

function ToJson($obj) { $obj | ConvertTo-Json -Depth 10 -Compress }
function Step($title) { Write-Host "`n--- $title ---" -ForegroundColor Cyan }

Step 'employee login'
$emp = Invoke-RestMethod -Method Post -Uri "$base/auth/login" `
    -ContentType 'application/json' `
    -Body (ToJson @{ phone='13800000000'; code='123456'; role='employee' })
$emp.data | ConvertTo-Json -Depth 10
$empId = $emp.data.id

Step 'merchant login'
$mer = Invoke-RestMethod -Method Post -Uri "$base/auth/login" `
    -ContentType 'application/json' `
    -Body (ToJson @{ phone='13900000000'; code='123456'; role='merchant' })
$mer.data | ConvertTo-Json -Depth 10

Step 'employee: list merchants'
$ms = Invoke-RestMethod -Method Get -Uri "$base/merchants"
"got $($ms.data.Count) merchants"
$selectedMerchant = $ms.data[0]
$selectedMerchant | ConvertTo-Json -Depth 10

Step "employee: list dishes of $($selectedMerchant.id)"
$ds = Invoke-RestMethod -Method Get -Uri "$base/merchants/$($selectedMerchant.id)/dishes"
"got $($ds.data.Count) dishes"
$dish = $ds.data[0]
$dish | ConvertTo-Json -Depth 10

Step 'employee: create order (Flutter-style body)'
$itemsBody = @(
    @{
        dish     = $dish
        quantity = 2
    }
)
$createBody = @{
    userId          = $empId
    merchantId      = $selectedMerchant.id
    merchantName    = $selectedMerchant.name
    customerName    = $emp.data.name
    customerCompany = 'A Park Admin'
    items           = $itemsBody
    deliveryType    = 'delivery'
    address         = 'Building 1F'
    phone           = '13800000000'
    remark          = 'no spicy'
    goodsAmount     = [double]($dish.price * 2)
    deliveryFee     = 3.0
    totalAmount     = [double]($dish.price * 2 + 3.0)
    status          = 'pendingMerchantConfirm'
    paymentScreenshot = $null
}
$order = Invoke-RestMethod -Method Post -Uri "$base/orders" `
    -ContentType 'application/json' -Body (ToJson $createBody)
$order.data | ConvertTo-Json -Depth 10
$orderId = $order.data.id
"orderId = $orderId"

Step 'employee: my orders'
$my = Invoke-RestMethod -Method Get -Uri "$base/orders/my?userId=$empId"
"got $($my.data.Count) my orders, latest status: $($my.data[0].status)"

Step 'merchant: list merchant orders'
$mo = Invoke-RestMethod -Method Get -Uri "$base/merchant/orders?merchantId=$($selectedMerchant.id)"
"merchant got $($mo.data.Count) orders"

Step 'merchant: accept order'
$r1 = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" `
    -ContentType 'application/json' -Body (ToJson @{ status='accepted' })
"after accept => $($r1.data.status)"

Step 'merchant: start delivering'
$r2 = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" `
    -ContentType 'application/json' -Body (ToJson @{ status='delivering' })
"after delivering => $($r2.data.status)"

Step 'merchant: complete'
$r3 = Invoke-RestMethod -Method Put -Uri "$base/orders/$orderId/status" `
    -ContentType 'application/json' -Body (ToJson @{ status='completed' })
"after complete => $($r3.data.status)"

Step 'employee: re-fetch own orders'
$my2 = Invoke-RestMethod -Method Get -Uri "$base/orders/my?userId=$empId"
$target = $my2.data | Where-Object { $_.id -eq $orderId }
"employee sees status: $($target.status)"

Write-Host "`n[OK] e2e flow finished" -ForegroundColor Green
