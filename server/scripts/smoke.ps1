$ErrorActionPreference = 'Stop'
$base = 'http://localhost:3000/api'

function Show($title, $obj) {
  Write-Host ''
  Write-Host "--- $title ---" -ForegroundColor Cyan
  $obj | ConvertTo-Json -Depth 8
}

Show 'GET /health' (Invoke-RestMethod -Uri "$base/health" -Method GET)

$loginEmp = Invoke-RestMethod -Uri "$base/auth/login" -Method POST `
  -ContentType 'application/json' `
  -Body (@{ phone='13800000000'; code='123456'; role='employee' } | ConvertTo-Json)
Show 'POST /auth/login employee' $loginEmp
$empId = $loginEmp.data.id

$loginMer = Invoke-RestMethod -Uri "$base/auth/login" -Method POST `
  -ContentType 'application/json' `
  -Body (@{ phone='13900000000'; code='123456'; role='merchant' } | ConvertTo-Json)
Show 'POST /auth/login merchant' $loginMer
$merUserId = $loginMer.data.id

$merchants = Invoke-RestMethod -Uri "$base/merchants" -Method GET
Show 'GET /merchants' $merchants
$firstMerchantId = $merchants.data[0].id
$firstMerchantName = $merchants.data[0].name

$profile = Invoke-RestMethod -Uri "$base/merchant/profile?userId=$merUserId" -Method GET
Show 'GET /merchant/profile' $profile
$selfMerchantId = $profile.data.id

$dishes = Invoke-RestMethod -Uri "$base/merchants/$firstMerchantId/dishes?mealType=lunch" -Method GET
Show 'GET /merchants/:id/dishes lunch' $dishes

$dishObj = @{
  id = 'tmp'; merchantId = $firstMerchantId; name = 'Lunch A';
  image='dish'; description='low fat'; price=16.8; mealType='lunch';
  tags=@(); isAvailable=$true
}
$dishObj2 = @{
  id = 'tmp'; merchantId = $firstMerchantId; name = 'Veggie';
  image='dish'; description=''; price=5.8; mealType='lunch';
  tags=@(); isAvailable=$true
}
$orderBody = @{
  userId          = $empId
  customerName    = 'Zhang San'
  customerCompany = 'A Park'
  merchantId      = $firstMerchantId
  merchantName    = $firstMerchantName
  deliveryType    = 'selfPickup'
  address         = 'Building 1F'
  phone           = '13800000000'
  remark          = 'less spicy'
  goodsAmount     = 22.6
  deliveryFee     = 0
  totalAmount     = 22.6
  items           = @(
    @{ dish = $dishObj;  quantity = 1 },
    @{ dish = $dishObj2; quantity = 1 }
  )
} | ConvertTo-Json -Depth 8
$createdOrder = Invoke-RestMethod -Uri "$base/orders" -Method POST `
  -ContentType 'application/json' -Body $orderBody
Show 'POST /orders' $createdOrder
$orderId = $createdOrder.data.id

$myOrders = Invoke-RestMethod -Uri "$base/orders/my?userId=$empId" -Method GET
Show 'GET /orders/my' $myOrders

$merchantOrders = Invoke-RestMethod -Uri "$base/merchant/orders?merchantId=$selfMerchantId" -Method GET
Show 'GET /merchant/orders self' $merchantOrders

$updated = Invoke-RestMethod -Uri "$base/orders/$orderId/status" -Method PUT `
  -ContentType 'application/json' -Body (@{ status='accepted' } | ConvertTo-Json)
Show 'PUT /orders/:id/status accepted' $updated

$newDish = Invoke-RestMethod -Uri "$base/dishes" -Method POST `
  -ContentType 'application/json' `
  -Body (@{
    merchantId  = $selfMerchantId
    name        = 'Test Dish'
    description = 'test desc'
    price       = 9.9
    mealType    = 'lunch'
    tags        = @('hot')
  } | ConvertTo-Json)
Show 'POST /dishes' $newDish
$dishId = $newDish.data.id

$editDish = Invoke-RestMethod -Uri "$base/dishes/$dishId" -Method PUT `
  -ContentType 'application/json' `
  -Body (@{ price=12.9; description='updated' } | ConvertTo-Json)
Show 'PUT /dishes/:id' $editDish

$toggleDish = Invoke-RestMethod -Uri "$base/dishes/$dishId/available" -Method PUT `
  -ContentType 'application/json' `
  -Body (@{ isAvailable=$false } | ConvertTo-Json)
Show 'PUT /dishes/:id/available' $toggleDish

Write-Host ''
Write-Host '[OK] Smoke test all passed.' -ForegroundColor Green
